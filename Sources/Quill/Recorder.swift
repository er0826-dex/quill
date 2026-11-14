import AVFoundation
import ObjCGuard
import FluidAudio

/// Keeps the microphone warm with a short rolling pre-roll in memory, so a press starts with the
/// audio from just before it (cold starts took 280–720 ms to deliver the first buffer, 10/30).
/// Dictation never writes to disk; the pre-roll overwrites itself. A meeting can also tee the same
/// tap into numbered CAF segments (`startFile` / `stopFile`) without disturbing dictation.
final class Recorder {
    static let sampleRate: Double = 16_000
    private static let preRollSeconds: Double = 0.5

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var preRoll: [Float] = []
    private var samples: [Float] = []
    private var capturing = false
    private var inputRate: Double = 48_000
    private let converter = AudioConverter(sampleRate: Recorder.sampleRate)
    private var configObserver: NSObjectProtocol?
    private var rms: Float = 0

    /// How loud the mic is right now, 0…1 (about -55 dB to -20 dB), for the bubble's glow.
    var level: Float {
        lock.lock(); let r = rms; lock.unlock()
        guard r > 0 else { return 0 }
        let db = 20 * log10(r)
        return min(1, max(0, (db + 55) / 35))   // -55 dB to -20 dB: ordinary speech reaches the top
    }
    // Meeting file: written from the tap thread, guarded by its own lock so dictation is never held up.
    private let fileLock = NSLock()
    private var segmentSource: (() -> URL)?     // non-nil while a meeting is recording
    private var segment: SegmentWriter?         // nil until the next buffer opens one
    private var segmentFailed = false

    /// Called on the main queue when the engine starts restarting after a device change (true) and
    /// when it is back (false). The meeting menu shows "recovering microphone" between the two.
    var onRecovery: ((Bool) -> Void)?

    private var restartWork: DispatchWorkItem?
    private var restartAttempt = 0

    /// Opens the mic and keeps it open. Restarts itself when the input device changes.
    func warmUp() throws {
        try startEngine()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Log.write("audio configuration changed; restarting the mic")
            self?.onRecovery?(true)
            self?.restartAttempt = 0
            self?.scheduleRestart(after: 0.3)
        }
    }

    /// A device change arrives as a burst of notifications while the old device is still going away
    /// (Bluetooth, sleep, a USB mic). Wait for it to settle, then retry until the mic comes back.
    private func scheduleRestart(after delay: TimeInterval) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try self.startEngine()
                if self.restartAttempt > 0 { Log.write("mic back after \(self.restartAttempt) retries") }
                self.restartAttempt = 0
                self.onRecovery?(false)
            } catch {
                self.restartAttempt += 1
                Log.write("mic restart failed (try \(self.restartAttempt)): \(error.localizedDescription)")
                self.scheduleRestart(after: self.restartAttempt < 5 ? 0.5 : 3)
            }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startEngine() throws {
        engine.stop()
        let input = engine.inputNode
        var guardError: NSError?
        _ = QuillTryObjC({ input.removeTap(onBus: 0) }, &guardError)
        let format = input.outputFormat(forBus: 0)
        // Mid-change the input can report no channels or no rate; installing a tap then throws.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        lock.lock(); inputRate = format.sampleRate; preRoll.removeAll(); lock.unlock()
        rollSegment()
        guardError = nil
        let installed = QuillTryObjC({ input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.writeToFile(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            var sum: Float = 0
            for x in chunk { sum += x * x }
            self.lock.lock()
            self.rms = chunk.isEmpty ? 0 : (sum / Float(chunk.count)).squareRoot()
            if self.capturing {
                self.samples.append(contentsOf: chunk)
            } else {
                self.preRoll.append(contentsOf: chunk)
                let keep = Int(self.inputRate * Self.preRollSeconds)
                if self.preRoll.count > keep { self.preRoll.removeFirst(self.preRoll.count - keep) }
            }
            self.lock.unlock()
        } }, &guardError)
        guard installed else { throw RecorderError.tap(guardError?.localizedDescription ?? "unknown") }
        engine.prepare()
        try engine.start()
    }

    func start() throws {
        if !engine.isRunning { try startEngine() }
        lock.lock()
        samples = preRoll
        preRoll.removeAll()
        capturing = true
        lock.unlock()
    }

    /// The capture so far, at 16 kHz, without stopping it. `lastSeconds` trims to the tail.
    func snapshot(lastSeconds: Double? = nil) -> [Float] {
        lock.lock()
        var raw = samples
        let rate = inputRate
        lock.unlock()
        if let lastSeconds {
            let keep = Int(rate * lastSeconds)
            if raw.count > keep { raw.removeFirst(raw.count - keep) }
        }
        return (try? converter.resample(raw, from: rate)) ?? []
    }

    /// Ends the capture and returns it at 16 kHz mono. The mic stays open.
    func stop() -> [Float] {
        lock.lock()
        capturing = false
        let raw = samples
        let rate = inputRate
        samples.removeAll()
        lock.unlock()
        return (try? converter.resample(raw, from: rate)) ?? []
    }

    // MARK: Meeting file

    /// Starts writing the mic to numbered CAF segments (`nextURL` names each one) from the running tap.
    /// A segment opens on the first buffer that arrives, converting whatever the input is to 16 kHz
    /// mono. Each engine restart (a device change, a gap in the audio) closes it, and the next
    /// buffer opens the next segment, so each file's start is its true place on the meeting clock.
    func startFile(nextURL: @escaping () -> URL) throws {
        fileLock.lock()
        segmentSource = nextURL
        segment = nil
        segmentFailed = false
        fileLock.unlock()
        if !engine.isRunning { try startEngine() }
    }

    /// Stops writing and closes the file. Dictation is untouched.
    func stopFile() {
        fileLock.lock()
        segment?.close()
        segment = nil
        segmentSource = nil
        fileLock.unlock()
    }

    /// The engine is restarting: close the current segment so the next buffer opens a new one.
    private func rollSegment() {
        fileLock.lock()
        if segment != nil { Log.write("mic file: engine restarted; next segment") }
        segment?.close()
        segment = nil
        segmentFailed = false
        fileLock.unlock()
    }

    private func writeToFile(_ buffer: AVAudioPCMBuffer) {
        fileLock.lock(); defer { fileLock.unlock() }
        guard let source = segmentSource, !segmentFailed else { return }
        if segment == nil {
            do { segment = try SegmentWriter(url: source()) }
            catch {
                segmentFailed = true
                Log.write("mic file couldn't open: \(error.localizedDescription)")
                return
            }
        }
        if let problem = segment?.write(buffer) {
            segmentFailed = true
            Log.write("mic file write failed, segment stops here: \(problem)")
        }
    }
}

enum RecorderError: LocalizedError {
    case noInput
    case tap(String)

    var errorDescription: String? {
        switch self {
        case .noInput: "no microphone input right now"
        case .tap(let why): "couldn't open the mic: \(why)"
        }
    }
}
