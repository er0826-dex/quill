import AVFoundation
import Foundation

/// What the menu can say about a meeting in progress.
enum MeetingStatus: Equatable {
    case ok
    case recoveringMic
    case recoveringSystem
    case systemLost
    case systemSilent
}

/// `meta.json` in a meeting folder: when it started and where each segment sits on the meeting clock.
/// The transcriber reads it to place every segment at its true time.
struct MeetingMeta: Codable {
    struct Segment: Codable {
        var file: String
        var track: String      // "mic" or "system"
        var offset: Double     // seconds after `started`
    }
    var version = 1
    var started: Date
    var segments: [Segment] = []
    var duration: Double?
}

/// The files of a meeting folder, new layout and old.
enum MeetingFiles {
    /// `mic.caf`, `mic-002.caf`, `system.caf`, `system-002.caf`, and the old `mic.m4a` / `system.m4a`.
    static func segments(in folder: URL) -> [(url: URL, track: String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.range(of: #"^(mic|system)(-\d+)?\.(caf|m4a)$"#, options: .regularExpression) != nil else { return nil }
            return (folder.appendingPathComponent(name), name.hasPrefix("mic") ? "mic" : "system")
        }
    }

    static func meta(in folder: URL) -> MeetingMeta? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MeetingMeta.self, from: data)
    }
}

/// Numbers the segments of a meeting, notes where each starts on the meeting clock, and keeps
/// `meta.json` current (written beside the audio on every change, off the audio threads).
final class MeetingLayout: @unchecked Sendable {
    let folder: URL
    private let startedUptime = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()
    private var meta: MeetingMeta
    private var counts: [String: Int] = [:]
    private let writer = DispatchQueue(label: "com.millwright.quill.meta")

    init(folder: URL) {
        self.folder = folder
        meta = MeetingMeta(started: Date())
        save()
    }

    /// The next file for a track, `mic.caf` then `mic-002.caf`; its offset is now.
    func nextURL(track: String) -> URL {
        lock.lock()
        let n = (counts[track] ?? 0) + 1
        counts[track] = n
        let name = n == 1 ? "\(track).caf" : String(format: "%@-%03d.caf", track, n)
        meta.segments.append(.init(file: name, track: track, offset: ProcessInfo.processInfo.systemUptime - startedUptime))
        lock.unlock()
        save()
        return folder.appendingPathComponent(name)
    }

    /// Drops segments whose file was never created (a restart that failed) and records the length.
    func finish(duration: TimeInterval) {
        lock.lock()
        meta.segments.removeAll { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.file).path) }
        meta.duration = duration
        lock.unlock()
        save()
        writer.sync {}
    }

    private func save() {
        lock.lock(); let snapshot = meta; lock.unlock()
        let url = folder.appendingPathComponent("meta.json")
        writer.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}

/// One segment file: 16 kHz mono 16-bit PCM in a CAF. Whatever input arrives (any rate, any channel
/// count, and a different one after a device change) is converted on the way in. Uncompressed on
/// purpose: a CAF's data chunk is open-ended, so a file the process died writing still reads up to
/// the last byte, which AAC does not (its packet table is only written on close; tested: after
/// `kill -9` an AAC .caf reads as 0 packets). The layout and numbering are adapted from
/// humanitas-labs/quill (MIT), whose tracks are numbered CAF segments too.
final class SegmentWriter: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private(set) var failed = false

    init(url: URL) throws {
        file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
    }

    /// Converts and appends one buffer. Returns an error text on the first failure, then nil.
    func write(_ buffer: AVAudioPCMBuffer) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let file, !failed, buffer.frameLength > 0 else { return nil }
        do {
            if converter == nil || inputFormat != buffer.format {
                if inputFormat != nil { Log.write("meeting file: input is now \(Int(buffer.format.sampleRate)) Hz x\(buffer.format.channelCount); converting") }
                converter = AVAudioConverter(from: buffer.format, to: file.processingFormat)
                inputFormat = buffer.format
            }
            guard let converter,
                  let out = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * Self.sampleRate / buffer.format.sampleRate) + 64)
            else { throw CocoaError(.fileWriteUnknown) }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if let error { throw error }
            if out.frameLength > 0 { try file.write(from: out) }
            return nil
        } catch {
            failed = true
            return error.localizedDescription
        }
    }

    /// Closes the file. Later writes (a stale callback) do nothing.
    func close() {
        lock.lock(); file = nil; converter = nil; lock.unlock()
    }
}

/// One meeting: the mic (from the warm `Recorder`'s tap) and the Mac's audio output, each to numbered
/// CAF segments in ~/Desktop/Quill Meetings/<date time>/, with `meta.json` beside them. The mic starts
/// a new segment whenever its engine restarts; the system track restarts itself into the next segment
/// when it stalls or the output route changes, up to three tries, then is marked lost. If the system
/// audio can't be captured at all, the mic keeps recording and `systemAudioProblem` says why.
@MainActor
final class MeetingRecorder {
    private enum SystemState { case ok, recovering, lost }

    private let recorder: Recorder
    private let system = SystemAudioRecorder()
    private var layout: MeetingLayout?

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var folder: URL?
    /// Why the system track is missing, when it is; nil when both tracks are recording.
    private(set) var systemAudioProblem: String?

    /// Called on the main actor whenever the status changes.
    var onStatus: ((MeetingStatus) -> Void)?
    /// Called once, with a plain sentence, when a track is lost for good.
    var onLost: ((String) -> Void)?

    private var systemState: SystemState = .ok
    private var micRecovering = false
    private var systemSilent = false
    private var stallStreak = 0
    private var lastStatus: MeetingStatus = .ok

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    static var baseFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Quill Meetings")
    }

    var status: MeetingStatus {
        if systemState == .lost { return .systemLost }
        if micRecovering { return .recoveringMic }
        if systemState == .recovering { return .recoveringSystem }
        if systemSilent { return .systemSilent }
        return .ok
    }

    private func publish() {
        let now = status
        guard now != lastStatus else { return }
        lastStatus = now
        onStatus?(now)
    }

    /// Creates the folder and starts both tracks. Throws only if the mic track can't start.
    @discardableResult
    func start() throws -> URL {
        guard !isRecording else { throw CocoaError(.fileWriteFileExists) }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let dir = Self.baseFolder.appendingPathComponent(stamp.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let layout = MeetingLayout(folder: dir)
        self.layout = layout

        systemState = .ok; micRecovering = false; systemSilent = false; stallStreak = 0; lastStatus = .ok
        recorder.onRecovery = { [weak self] recovering in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.micRecoveryChanged(recovering) } }
        }
        try recorder.startFile { layout.nextURL(track: "mic") }
        do {
            try system.begin(url: layout.nextURL(track: "system")) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
            }
            systemAudioProblem = nil
        } catch {
            systemAudioProblem = "\(error)"
            systemState = .lost
            Log.write("meeting: system audio not captured: \(error)")
        }
        folder = dir
        startedAt = Date()
        isRecording = true
        Log.write("meeting started, system audio \(systemAudioProblem == nil ? "on" : "off")")
        publish()
        return dir
    }

    /// Stops both tracks. Returns the folder and the length of the recording.
    @discardableResult
    func stop() -> (folder: URL, duration: TimeInterval)? {
        guard isRecording, let folder, let startedAt else { return nil }
        isRecording = false
        recorder.stopFile()
        recorder.onRecovery = nil
        system.finish()
        self.startedAt = nil
        let duration = Date().timeIntervalSince(startedAt)
        layout?.finish(duration: duration)
        layout = nil
        systemState = .ok; micRecovering = false; systemSilent = false
        publish()
        Log.write("meeting stopped after \(Int(duration)) s")
        return (folder, duration)
    }

    // MARK: Recovery

    private func micRecoveryChanged(_ recovering: Bool) {
        guard isRecording else { return }
        micRecovering = recovering
        Log.write(recovering ? "meeting: microphone recovering" : "meeting: microphone recovered; next segment")
        publish()
    }

    private func handle(_ event: SystemAudioRecorder.Event) {
        guard isRecording, systemState != .lost else { return }
        switch event {
        case .silent(let silent):
            systemSilent = silent
            publish()
        case .healthy:
            stallStreak = 0
        case .routeChanged:
            guard systemState == .ok else { return }
            Log.write("meeting: output device changed; restarting system audio")
            recoverSystem(attempt: 1, delay: 0.8)
        case .stalled:
            guard systemState == .ok else { return }
            stallStreak += 1
            Log.write("meeting: system audio stalled (stall \(stallStreak) of 3)")
            if stallStreak > 3 { lose("it kept stalling"); return }
            recoverSystem(attempt: 1, delay: 0.3)
        }
    }

    /// Tears the tap down and starts it again in the next numbered segment, three tries.
    private func recoverSystem(attempt: Int, delay: TimeInterval) {
        guard let layout else { return }
        systemState = .recovering
        publish()
        system.restart(url: layout.nextURL(track: "system"), after: delay) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.isRecording, self.systemState == .recovering else { return }
                if let error {
                    Log.write("meeting: system audio restart failed (try \(attempt) of 3): \(error)")
                    if attempt < 3 { self.recoverSystem(attempt: attempt + 1, delay: Double(attempt)) }
                    else { self.lose("\(error)") }
                } else {
                    Log.write("meeting: system audio back after \(attempt) \(attempt == 1 ? "try" : "tries")")
                    self.systemState = .ok
                    self.publish()
                }
            }
        }
    }

    private func lose(_ why: String) {
        systemState = .lost
        systemAudioProblem = why
        system.finish()
        Log.write("meeting: system audio lost: \(why)")
        publish()
        onLost?("system audio")
    }
}
