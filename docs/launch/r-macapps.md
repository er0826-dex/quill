Title: Quill: free, local hold-to-talk dictation for the Mac (also records meetings)

Body:

I dictate all day and wanted something that was fast, free, and kept my audio on the Mac, so I built Quill and I'm sharing it.

What it does: hold Right Option (or Right Command, Right Control, Left Option, Fn), speak, release, and the text is pasted at the cursor in any app. A small bubble beside the cursor shows the words live while you talk. Your clipboard is restored afterward.

What's different from other dictation apps I've used:

- Live words at the cursor, not only after you release.
- It never pastes into the wrong app. If focus moved, it holds the text and you choose Paste Last Transcript or Copy Last Transcript from the menu. No history is kept, by design; only the last dictation, in memory.
- Local and free. Transcription is on-device (Parakeet TDT v2, about 0.5 GB, downloaded once). No account, no telemetry.
- Meetings too. Start and Stop from the menu records your mic and system audio as separate tracks (crash-safe CAF files, survives AirPods connecting mid-call), then transcribes on-device (Parakeet by default, Whisper Large v3 Turbo optional) into a transcript with Me/Them.

Honest limits: English only, Apple Silicon only, macOS 15 or later, and it's new. The first meeting transcription needs a ~1.5 GB model and a one-time 10-15 minute Neural Engine compile.

Install with `brew install --cask millwright-software/tap/quill` or download the notarized zip from the releases page.

Repo (MIT): https://github.com/millwright-software/quill
Page: https://millwrightsoftware.com/quill/

Feedback welcome, especially apps where the paste misbehaves: support@millwrightsoftware.com
