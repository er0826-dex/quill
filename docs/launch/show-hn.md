Title: Show HN: Quill, free local dictation for macOS with live words at the cursor

URL: https://github.com/millwright-software/quill

Text:

I dictate most of my day, and I wasn't happy with the dictation tools I tried, so I built one for myself and then cleaned it up to share.

Quill is a macOS menu-bar app. You hold Right Option, talk, and let go; the text is pasted at the cursor in whatever app you're in. While you hold the key, a small bubble beside the cursor shows your words as you say them. Transcription runs on-device (Parakeet TDT v2 through FluidAudio). No account, no telemetry, free, MIT licensed.

Two things I cared about. First, it should never paste into the wrong app: if focus moves before the text lands, Quill holds it and you paste or copy it from the menu. It keeps the last dictation in memory for that reason and keeps no history on purpose. Second, the words should appear while you speak, not after.

It also records meetings: your mic and the system audio as separate tracks, saved as CAF files so a crash mid-meeting doesn't lose the recording, then transcribed on-device into a timestamped transcript with Me/Them: Parakeet by default (an hour in about a minute), Whisper Large v3 Turbo if you prefer it. Recording keeps going through a device change like AirPods connecting.

Limits: English only, Apple Silicon only, macOS 15 or later. It's new, so expect rough edges. The system-audio capture code is adapted from humanitas-labs/quill (MIT), a different project that records meetings but doesn't do dictation.

Install: brew install --cask millwright-software/tap/quill, or the notarized zip on the releases page. Page: https://millwrightsoftware.com/quill/

I'd like to hear which apps it misbehaves in and what else you'd want from dictation. support@millwrightsoftware.com or issues on GitHub.
