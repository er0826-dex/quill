# Quill: the brief

A menu-bar app that replaces the two MacWhisper features Eric uses. Started 10/30/2026. Name: Eric's pick from Wren, Mynah, Lyre, Quill, Trill, Perch ("a feather you write with: bird into words").

## Who it's for

One user, Eric: Apple Silicon Mac, macOS 15 (Sequoia) at the time of writing, Xcode 26 and Swift 6.2 installed. Often dictates into a terminal or a chat box. Speed from release-of-key to text-on-screen matters more than anything else. Keep it minimal; MVP first, then iterate.

## The two features

1. **Hold to talk → paste at cursor.** A global hotkey (a held modifier: option or right-command, configurable). Start capture on press, stop on release, transcribe, insert at the cursor in whatever app has focus. Must not clobber the clipboard: save it, paste, restore it.
2. **Record → transcribe.** From the menu: record, stop, transcribe; show the text with Copy and Save. Optionally transcribe a dropped audio file.

## Constraints

- Local only. No network at runtime except a one-time model download. No telemetry.
- Menu-bar only (no Dock icon). A small status mark shows idle, listening, transcribing.
- macOS permissions it will need, each asked for by the system and explained in-app: Microphone (capture), Accessibility (the global key and synthesizing the paste).
- Ships as a signed local build Eric can run; no App Store.

## Decisions to make first (walk them with Eric, one at a time, multiple choice)

1. **Language and shape.** Native Swift / SwiftUI `MenuBarExtra` (recommended: the hotkey, paste and permissions are native APIs, and the speech engines below are Swift packages) vs. a Python menu-bar app (`rumps`) on the mlx-whisper / parakeet-mlx stack (faster to prototype, messier permissions and packaging).
2. **The speech engine.** Candidates, to verify against their repos before choosing: Parakeet via FluidAudio (Core ML, very fast English), Whisper via WhisperKit (argmaxinc, broader languages), whisper.cpp. Possibly offer two: a fast default and an accurate one for longer recordings.
3. **The hotkey.** Which key, and hold-to-talk only or also a press-to-toggle mode for long dictation.
4. **Where recordings go.** Kept (a folder, a retention period) or thrown away after transcribing.

## Prior art to read before building (open source, same problem)

Several menu-bar dictation apps already combine these engines; read how they do the hotkey, the paste and the engine switch rather than reinventing it: Hex (dizk/Hex), MacParakeet (moona3k), Ghost Pepper (matthartman), Muesli (forjd), Voicey (jonathanKingston), wispr (sebsto), digimata/quill (a meeting recorder that shares the name). Verify each before relying on it.

## Decisions made

1. **Shape (10/30): native Swift menu-bar app.** SwiftUI `MenuBarExtra`, SwiftPM, no Dock icon, signed with Eric's Developer ID so the Accessibility grant survives rebuilds.
2. **Engine (10/30): FluidAudio Parakeet TDT v2 (English).** Eric's criterion: the most accurate. Parakeet v2's model card reports 6.05% average WER on the Open ASR leaderboard's 8 English sets; Whisper large-v3-turbo is ~7.8% from memory (the leaderboard CSV is login-gated, unverified). It is also the faster one. WhisperKit turbo as a second engine, compared on Eric's own voice, is in IDEAS. FluidAudio v0.18.0 (10/28): every `transcribe` overload takes `decoderState: inout` (the README is stale).
3. **Hotkey (10/30): hold Right Option** (keycode 61), via a CGEventTap. A hold under 0.3 s is discarded; another key or a click in the first 0.5 s cancels (an Option chord). After 0.5 s the hold is committed and only the release ends it (10/30: Hex's cancel-anytime rule threw away a 13.7 s dictation). Hold-to-talk only in v0.1.
4. **Recordings (10/30): never on disk; kept in memory until the paste is confirmed** (Eric: in MacWhisper, "if something grabs the screen focus while I'm transcribing… I lose the audio because it doesn't have anywhere to paste it"). The app frontmost at key-press is the paste target. If another app is frontmost when the text is ready, Quill does not paste: it holds the transcript, marks the icon, and the menu offers Paste / Copy / Re-transcribe. The last clip and text stay in memory until the next dictation pastes. **No history, by design** (Eric 10/31: "I don't want history"): only the most recent dictation, in memory, as the focus-grab backstop; nothing on disk. "Confirmed" means Cmd-V went to the same app; macOS cannot confirm that a paste landed, so the menu copy is the backstop.
5. **Mic warm for a while after use (11/15, Eric).** Settings → "Keep the mic ready after dictating": Off / 30 s / 1 min (default) / 5 min. The mic opens on the first press and stays open that long after the last release, then closes; while open it keeps only a rolling half second in memory (instant start with the moment before the press), transcribes nothing, and macOS shows its indicator. Off = only while held. The red feather means the key is held and Quill is capturing for a dictation. Before that: **Mic only while held (11/14, Eric), replacing the warm mic.** The mic opens on the press and closes on release (or stays open while a meeting records), so macOS's mic indicator isn't on all day. The first buffer takes ~150–700 ms; the bubble appears only when audio is flowing, so it means "speak". The menu-bar feather is red while listening. Superseded: **Warm mic (10/30, Eric: yes).** The mic stays open while Quill runs, with a 0.5 s rolling pre-roll in memory, so a press starts with the audio just before it. Cold starts took 280–720 ms to deliver the first buffer and cut the first words. The cost: macOS's orange mic dot stays on.
6. **The bubble (v0.2, 10/30–31, tuned with Eric until "much better").** A glowing capsule just below the text cursor (Accessibility caret bounds; else below the focused field; else by the mouse). On the left, the quill silhouette slowly writing back and forth along a faint baseline. On the right, a ticker of the live words in soft grey, about four words wide (130 pt): a constant 60 pt/s, right to left, fading in at the right and out at the left; a word joins once two live passes (every 0.4 s) agree on it; a pause is a gap; a long queue skips ahead rather than lag. On release no new words; the bubble fades out over 1.4 s, eased. Held shows "Held, not pasted: Quill menu → Paste". The paste is still one full pass on release. Live preview is a toggle. Lessons: implicit SwiftUI repeat-forever animations also animate layout (the icon slid); drive motion from the display link or a TimelineView instead.

**Meeting engine (11/14, Eric): Parakeet by default, Whisper Large v3 Turbo as the Settings option.** Parakeet runs on its own AsrManager (dictation never waits), token timings become lines split at a 0.8 s pause measured from the last word (a full stop can be timed after the pause and belongs to the sentence before), or at a sentence end past 12 s. Tested: a 20 s two-voice meeting in 1.0 s including the model load; a 2:46 one with every line at its true time across the 15 s windows.

## Meeting mode (v0.3, built 10/31)

**0.4 (11/14): crash-safe and self-healing.** Tracks are 16 kHz mono PCM in CAF (`mic.caf`, `system.caf`, then `-002`… segments after a device change), plus `meta.json` with each segment's offset; a killed Quill leaves every second up to the kill readable (AAC in CAF was not: its packet table is written on close). ~115 MB/hour per track. The system tap watches route changes and a 1 s callback watchdog, restarts up to 3 times, then marks the track lost (Basso + notification); the menu shows "Recovering microphone…", "System audio lost…", "System audio is silent". The original 0.3 layout follows.

Menu → **Start Meeting Recording**: two tracks into `~/Desktop/Quill Meetings/YYYY-MM-DD HHmm/`, `mic.m4a` (from the warm mic's own tap, so dictation keeps working) and `system.m4a` (everything the Mac plays, through a Core Audio process tap adapted from humanitas-labs/quill, MIT; needs the Screen & System Audio Recording permission). The icon becomes a record mark; the menu shows a running timer. **Stop** (or Quit) saves, and an alert offers to transcribe with **Whisper Large v3 Turbo** via WhisperKit (argmax-oss-swift 1.1.1; Eric's pick for meetings; dictation stays on Parakeet). The transcript is `transcript.md` beside the audio, Me (mic) and Them (system) by track, timestamped; it opens in the background when done. The model (1.5 GB) lives in `~/Library/Application Support/Quill/Models`, loads only to transcribe, and is released after. First load compiles for the Neural Engine (~12 min, once); later loads ~3.5 s; ~10x realtime. A denied system-audio permission records silence, not an error, so a silent system track is flagged in the alert.

Later: a live view during the meeting (Parakeet, like the bubble); speaker labels within "Them" (FluidAudio's Diarizer); untested so far: meetings over a minute, a device change mid-meeting.

## Name collision

Other projects are called Quill, including an open-source macOS voice-typing app and digimata/quill. Fine for a personal tool; revisit only if this is ever shared.

## How to work here

- One session builds. Smallest shippable version first: feature 1 alone, one engine, one hotkey, is v0.1.
- Test the real thing: build, run, hold the key in TextEdit and in a terminal, measure release-to-text time.
- Commit as you go; this repo is its own history.
