# Quill

Hold a key, talk. It writes. Free and local. Records meetings too.

Quill is a small menu-bar app for macOS. Hold Right Option, speak, let go: the text is pasted at your cursor in whatever app you're in. A small bubble beside the cursor shows your words as you say them. Everything runs on your Mac. No account, no subscription, no cloud.

![Quill dictating](docs/quill-bubble.png)

## Install

With Homebrew:

```sh
brew install --cask millwright-software/tap/quill
```

Or download `Quill.zip` (signed and notarized by Apple) from the [Releases page](https://github.com/millwright-software/quill/releases/latest), unzip it, and drag Quill to Applications.

## First run

Quill opens a welcome window that explains what it needs and checks it for you:

- **Microphone**, to hear you.
- **Accessibility**, to paste the text at your cursor.
- **A model download**, about 0.5 GB, once. Dictation is ready a minute or so after.

## How to use

Hold **Right Option**, speak, release. The text is pasted where the cursor is. Your clipboard is restored afterward.

- The bubble shows the live words while you hold the key.
- If you switch apps before the paste, Quill holds the text instead of pasting it into the wrong place. Choose **Paste Last Transcript** or **Copy Last Transcript** from the menu-bar icon.
- **Settings** has the hotkey (Right Option, Right Command, Right Control, Left Option or Fn), the live preview toggle, and launch at login.

## Meetings

Choose **Start Meeting Recording** from the menu and **Stop** when you're done. Quill records your microphone and the Mac's system audio (the other people on the call) as separate tracks. The first time, macOS asks for System Audio Recording permission.

Each meeting is saved in `~/Desktop/Quill Meetings/<date time>/`. Recording is crash-safe: audio goes to `.caf` files (`mic.caf`, `system.caf`, plus numbered segments if a track restarts) that stay readable even if Quill quits mid-meeting, and a device change such as AirPods connecting does not end the recording.

After you stop, Quill offers to transcribe. By default it uses Parakeet, the model dictation already has, so an hour of audio takes about a minute. Settings → Meetings switches to Whisper Large v3 Turbo instead (about 1.5 GB, downloaded once, plus a one-time 10–15 minute Neural Engine compile on first use). The result is `transcript.md`, timestamped, with your words labeled **Me** and everyone else **Them**.

## Privacy

- Transcription is on-device. There is no account and no telemetry.
- The only network traffic is the one-time model downloads from Hugging Face.
- Dictation audio is held in memory only and never written to disk.
- Quill keeps only your last dictation, in memory, so a stolen focus can't lose it. There is no history, by design.
- Meeting audio and transcripts are saved on your Mac, in the folder above, and nowhere else.

## Requirements

macOS 15 or later, on an Apple Silicon Mac. English only for now.

## Build from source

Needs Xcode 26 (Swift 6.2).

```sh
git clone https://github.com/millwright-software/quill.git
cd quill
scripts/build.sh --run      # builds, installs /Applications/Quill.app, launches it
```

The first build fetches the Swift packages (FluidAudio, WhisperKit). Models download on first use as described above.

`build.sh` signs with the Developer ID it is configured for when the Mac has it, otherwise ad-hoc; set `QUILL_SIGN_IDENTITY` to use your own. Ad-hoc builds work, but macOS asks for the permissions again after each rebuild. Models live in `~/Library/Application Support/` (`FluidAudio`, `Quill/Models`); the log is `~/Library/Logs/Quill.log` (timings and counts, never your words). See `CLAUDE.md` for the design notes and `IDEAS.md` for the running list.

## Release

Maintainers: `scripts/release.sh <version>` builds, signs with the Developer ID, notarizes, staples, tags and publishes the GitHub release (`--dry-run` stops after the signed build). It then prints the zip's SHA-256 and writes the version and hash into `Casks/quill.rb`; copy that file into the `millwright-software/homebrew-tap` repo and push it.

## Credits and license

MIT (see `LICENSE`). Speech models: NVIDIA Parakeet TDT 0.6B v2 (CC-BY-4.0) via FluidAudio (Apache-2.0); Whisper Large v3 Turbo via WhisperKit (MIT). System-audio capture is adapted from humanitas-labs/quill (MIT).

Questions or problems: support@millwrightsoftware.com
