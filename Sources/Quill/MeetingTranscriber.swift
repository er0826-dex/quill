import AVFoundation
import Foundation
import WhisperKit

/// Whisper Large v3 Turbo (full size) through WhisperKit, for meeting recordings. Dictation stays on
/// Parakeet (Transcriber). The model is downloaded on first use, loaded when a transcription starts
/// and released when it ends, so the ~1.5 GB of weights never sit in memory between meetings.
actor MeetingTranscriber {
    /// The WhisperKit variant; its folder in argmaxinc/whisperkit-coreml is `openai_whisper-` + this.
    static let modelName = "large-v3-v20240930_turbo"

    /// Below this RMS a whole track is treated as silence (an empty system track from an in-person meeting).
    private static let silenceRMS: Float = 0.002

    private static let modelsFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Quill/Models")

    private static let fillers: Set<String> = ["you", "thank you", "thanks", "thanks for watching", "bye"]

    private struct Line {
        var start: Float
        var end: Float
        var speaker: String
        var text: String
    }

    /// One audio file placed on the meeting clock: `offset` seconds after the start.
    private struct Segment {
        var url: URL
        var speaker: String
        var offset: Float
    }

    /// Transcribes every `mic*.caf` as "Me" and `system*.caf` as "Them" (the old `mic.m4a` and
    /// `system.m4a` too; any may be missing), each at its offset from `meta.json`, merges all by start
    /// time into `transcript.md` beside them, and returns its URL.
    func transcribe(folder: URL, progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        let tracks = Self.segments(in: folder)
        guard !tracks.isEmpty else { throw MeetingError.noAudio }

        let started = Date()
        let kit = try await loadModel(progress: progress)
        Log.write("meeting: model ready in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")

        var lines: [Line] = []
        for (n, track) in tracks.enumerated() {
            progress("Transcribing \(track.speaker)\(tracks.count > 2 ? " (\(n + 1) of \(tracks.count))" : "")…")
            do {
                lines += try await transcribe(track, with: kit)
            } catch {
                // A segment cut off by a crash or a failed restart shouldn't sink the rest.
                Log.write("meeting: \(track.url.lastPathComponent) skipped: \(error.localizedDescription)")
            }
        }
        await kit.unloadModels()

        progress("Writing transcript…")
        let transcript = folder.appendingPathComponent("transcript.md")
        try Self.markdown(lines, title: folder.lastPathComponent).write(to: transcript, atomically: true, encoding: .utf8)
        Log.write("meeting: transcript of \(lines.count) segments in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        return transcript
    }

    private func loadModel(progress: @escaping @Sendable (String) -> Void) async throws -> WhisperKit {
        let label = "Downloading Whisper Large v3 Turbo…"
        progress(label)
        try? FileManager.default.createDirectory(at: Self.modelsFolder, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: Self.modelName, downloadBase: Self.modelsFolder) { p in
            progress("\(label) \(Int(p.fractionCompleted * 100))%")
        }
        progress("Loading model…")
        let config = WhisperKitConfig(
            downloadBase: Self.modelsFolder, modelFolder: folder.path,
            verbose: false, logLevel: .none, prewarm: false, load: true, download: false
        )
        return try await WhisperKit(config)
    }

    /// The folder's segments with their offsets: from `meta.json`, else from when each file was created
    /// (a folder from a crash before the first write), else 0 (the old two-file layout).
    private static func segments(in folder: URL) -> [Segment] {
        let meta = MeetingFiles.meta(in: folder)
        let files = MeetingFiles.segments(in: folder)
        func created(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.creationDateKey]).creationDate }
        let first = files.compactMap { created($0.url) }.min()
        return files.map { file in
            let name = file.url.lastPathComponent
            var offset = 0.0
            if let entry = meta?.segments.first(where: { $0.file == name }) {
                offset = entry.offset
            } else if name.hasSuffix(".caf"), let first, let date = created(file.url) {
                offset = date.timeIntervalSince(first)
            }
            return Segment(url: file.url, speaker: file.track == "mic" ? "Me" : "Them", offset: Float(offset))
        }
    }

    private func transcribe(_ segment: Segment, with kit: WhisperKit) async throws -> [Line] {
        let url = segment.url, speaker = segment.speaker, offset = segment.offset
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
        guard rms >= Self.silenceRMS else {
            Log.write("meeting: \(url.lastPathComponent) is silent (rms \(rms)); skipped")
            return []
        }
        // Word timestamps: segment times alone drift after silence (a reply after 7 s of quiet started at 0:00).
        let options = DecodingOptions(task: .transcribe, language: "en", detectLanguage: false, wordTimestamps: true)
        let t0 = Date()
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        Log.write("meeting: \(url.lastPathComponent) \(samples.count / 16_000) s of audio in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        return results.flatMap(\.segments).compactMap { seg in
            // Whisper's own rule for a segment with no speech in it.
            if seg.noSpeechProb > 0.6 && seg.avgLogprob < -1 { return nil }
            let text = Self.clean(seg.text)
            let start = seg.words?.first?.start ?? seg.start
            let end = seg.words?.last?.end ?? seg.end
            // Whisper's stock hallucinations on near-silence: a lone "you" or "thank you" under a second long.
            if end - start < 1, Self.fillers.contains(text.lowercased().trimmingCharacters(in: .punctuationCharacters)) { return nil }
            // A timestamp past the end of the audio, or no word at all ("-"), is Whisper filling silence.
            guard start < Float(samples.count) / 16_000, text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return Line(start: start + offset, end: end + offset, speaker: speaker, text: text)
        }
    }

    /// Strips Whisper's special tokens and bracketed non-speech ([BLANK_AUDIO], [Music]).
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>|\[[^\]]*\]|♪+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lines by start time; the same speaker starting within 2 s of the last segment's end continues one paragraph.
    private static func markdown(_ lines: [Line], title: String) -> String {
        var merged: [Line] = []
        for line in lines.sorted(by: { $0.start < $1.start }) {
            if var last = merged.last, last.speaker == line.speaker, line.start - last.end <= 2 {
                last.text += " " + line.text
                last.end = line.end
                merged[merged.count - 1] = last
            } else {
                merged.append(line)
            }
        }
        let date = title.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression).map { String(title[$0]) } ?? title
        var out = "# Meeting, \(date)\n"
        for line in merged {
            let s = Int(line.start)
            let stamp = String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            out += "\n**[\(stamp)] \(line.speaker):** \(line.text)\n"
        }
        return out
    }
}

enum MeetingError: LocalizedError {
    case noAudio
    var errorDescription: String? { "the meeting folder has no recorded audio (mic or system)" }
}
