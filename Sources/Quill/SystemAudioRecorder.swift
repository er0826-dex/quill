import AVFoundation
import CoreAudio

/// Records everything the Mac plays through a Core Audio process tap (macOS 14.2+): a global stereo
/// tap, read through a private aggregate device, written to CAF segments (`SegmentWriter`). The first
/// use asks for the system's audio-capture permission. Adapted from humanitas-labs/quill (MIT), whose
/// numbered segments and callback watchdog this follows.
///
/// A tap can go quiet after a route change (AirPods connect, a display's speakers take over). So the
/// recorder watches the default output device and the device list, and once a second checks that the
/// IO callback is still running; it reports `Event`s on the main queue and `MeetingRecorder` decides
/// what to do. A segment is one tap + aggregate + file; recovery is `restart` into the next file.
final class SystemAudioRecorder: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    enum Event {
        case routeChanged        // the default output or the device list changed
        case stalled             // the IO callback stopped running
        case healthy             // a segment has run 10 s without a stall
        case silent(Bool)        // the whole meeting so far is (or is no longer) digital silence
    }

    /// Counters shared by the IO callback (any thread) and the one-second watchdog (main).
    private final class Stats: @unchecked Sendable {
        private let lock = NSLock()
        private var lastCallback = 0.0
        private var segmentStarted = 0.0
        private var active = false
        private var stallReported = false
        private var healthyReported = false
        private var peak: Float = 0
        private var began = 0.0
        private var silentReported = false

        func beginMeeting() {
            lock.lock(); peak = 0; began = now; silentReported = false; lock.unlock()
        }
        func beginSegment() {
            lock.lock(); active = true; segmentStarted = now; lastCallback = 0; stallReported = false; healthyReported = false; lock.unlock()
        }
        func endSegment() { lock.lock(); active = false; lock.unlock() }
        func callback(peak p: Float) {
            lock.lock(); lastCallback = now; if p > peak { peak = p }; lock.unlock()
        }
        var segmentAge: Double { lock.lock(); defer { lock.unlock() }; return now - segmentStarted }

        /// The events due now, from the counters.
        func due() -> [Event] {
            lock.lock(); defer { lock.unlock() }
            var events: [Event] = []
            let t = now
            if active, !stallReported, t - max(lastCallback, segmentStarted + 1) > 1 {
                stallReported = true
                events.append(.stalled)
            } else if active, !healthyReported, lastCallback > segmentStarted, t - segmentStarted > 10 {
                healthyReported = true
                events.append(.healthy)
            }
            if t - began > 20 {
                let silent = peak < 0.001
                if silent != silentReported { silentReported = silent; events.append(.silent(silent)) }
            }
            return events
        }
        private var now: Double { ProcessInfo.processInfo.systemUptime }
    }

    /// Start, stop and restart all run here, one at a time, so a slow Core Audio call never holds the main thread.
    private let control = DispatchQueue(label: "com.millwright.quill.system-control")
    private let ioQueue = DispatchQueue(label: "com.millwright.quill.system-tap")
    private let stats = Stats()
    private var wanted = false                       // control queue only
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var writer: SegmentWriter?

    private var onEvent: (@Sendable (Event) -> Void)?
    private var timer: DispatchSourceTimer?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    // MARK: Session

    /// Starts watching and writes the first segment. Throws, with everything released, if the tap can't start.
    func begin(url: URL, onEvent: @escaping @Sendable (Event) -> Void) throws {
        self.onEvent = onEvent
        stats.beginMeeting()
        try control.sync {
            wanted = true
            do { try startSegment(url: url) } catch { wanted = false; throw error }
        }
        startWatching()
    }

    /// Replaces the tap and the file with a fresh segment after `delay`; `completion` runs on main.
    func restart(url: URL, after delay: TimeInterval, completion: @escaping @Sendable (Error?) -> Void) {
        control.asyncAfter(deadline: .now() + delay) { [self] in
            guard wanted else { return }
            stopSegment()
            var failure: Error?
            do { try startSegment(url: url) } catch { failure = error }
            DispatchQueue.main.async { completion(failure) }
        }
    }

    /// Ends the session: stops watching and closes the last segment.
    func finish() {
        stopWatching()
        control.sync {
            wanted = false
            stopSegment()
        }
        onEvent = nil
    }

    // MARK: Watching

    private func startWatching() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, let onEvent = self.onEvent else { return }
            for event in self.stats.due() { onEvent(event) }
        }
        timer.resume()
        self.timer = timer

        // The tap's own aggregate device shows up in the device list when a segment starts; ignore
        // changes right after one so a restart can't trigger the next.
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.stats.segmentAge > 3 else { return }
                self.onEvent?(.routeChanged)
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    private func stopWatching() {
        timer?.cancel()
        timer = nil
        for (var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        listeners.removeAll()
    }

    // MARK: One segment (control queue)

    /// Creates the tap, the aggregate device and the file, then starts writing. Throws, with
    /// everything it made already released, if any step fails.
    private func startSegment(url: URL) throws {
        guard tapID == kAudioObjectUnknown else { throw Failure(description: "already recording") }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "quill system tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr else {
            throw Failure(description: "the audio tap was refused (OSStatus \(tapStatus)); allow Quill under System Settings → Privacy & Security → Screen & System Audio Recording")
        }
        tapID = newTap

        do {
            let format = try tapFormat()
            try makeAggregate(tapUUID: description.uuid)
            let segment = try SegmentWriter(url: url)
            writer = segment
            stats.beginSegment()
            try startIO(format: format, segment: segment)
        } catch {
            stopSegment()
            throw error
        }
    }

    /// Stops the device, destroys the IO proc, the aggregate device and the tap, and closes the file.
    /// Safe after a partial start.
    private func stopSegment() {
        stats.endSegment()
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        // Let a callback already running finish before the file closes.
        ioQueue.sync {}
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        writer?.close()
        writer = nil
    }

    private func tapFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw Failure(description: "could not read the tap's format (OSStatus \(status))")
        }
        return format
    }

    private func makeAggregate(tapUUID: UUID) throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "quill-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id)
        guard status == noErr else {
            throw Failure(description: "could not create the aggregate device (OSStatus \(status))")
        }
        aggregateID = id
    }

    private func startIO(format: AVAudioFormat, segment: SegmentWriter) throws {
        // The callback holds only this segment's writer and the counters, never `self`, so a callback
        // from a torn-down segment can't touch the next one's file.
        let stats = self.stats
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) {
            _, inInputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil)
            else { return }
            stats.callback(peak: Self.peak(of: buffer))
            if let problem = segment.write(buffer) {
                Log.write("system audio write failed, segment stops here: \(problem)")
            }
        }
        guard status == noErr, procID != nil else {
            throw Failure(description: "could not create the IO proc (OSStatus \(status))")
        }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            throw Failure(description: "could not start the device (OSStatus \(status))")
        }
    }

    private static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        var peak: Float = 0
        if buffer.format.isInterleaved {
            for i in 0..<(frames * Int(buffer.format.channelCount)) { peak = max(peak, abs(data[0][i])) }
        } else {
            for c in 0..<Int(buffer.format.channelCount) {
                for i in 0..<frames { peak = max(peak, abs(data[c][i])) }
            }
        }
        return peak
    }
}
