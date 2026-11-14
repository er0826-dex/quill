# Quill 0.4: ready for strangers (plan, 11/14)

Eric, 11/14: publish it, free, keep the name; set it apart from humanitas-labs/quill (a meeting recorder, no dictation, build-from-source) by what it does that theirs doesn't. "Let's do all the changes needed… get a page up on Millwright."

Tagline: **Hold a key, talk. It writes. Free and local. Records meetings too.**

## Workstreams (parallel agents, each on its own branch and files)

| | What | Branch / repo | Owns |
|---|---|---|---|
| A | **Meetings you can trust**: record to CAF (readable if Quill dies mid-meeting; m4a is not), keep recording through a device change (AirPods), system audio restarts into a numbered segment, the menu says when a track is recovering or lost, the transcriber reads CAF and segments | `quill` · `meeting-robust` | Recorder (file part), SystemAudioRecorder, MeetingRecorder, Meetings, MeetingTranscriber |
| B | **First run**: a welcome window that explains and checks Microphone and Accessibility, a "try it" field to test dictation, the hotkey choice; reopenable from the menu | `quill` · `onboarding` | new Onboarding.swift, small hooks in QuillApp / AppModel |
| C | **The page**: millwrightsoftware.com/quill/, the pitch, an animated HTML/CSS demo of the bubble, the download button (latest notarized release), the comparison, privacy, requirements, credits; linked from the home page | `millwright-site` · `quill-page` | quill/ folder, one link on index.html |
| D | **For strangers**: README rewritten for a stranger (what, install, permissions, privacy, meetings, build from source, credits), CHANGELOG, a Homebrew cask template, launch post drafts (Show HN, r/macapps) | `quill` · `docs` | README, CHANGELOG, Casks/, docs/launch/ |

## Then (this session, after review)

1. Merge A, B, D; build; test dictation, a meeting with a device change, a forced crash mid-meeting (the CAF must still transcribe), first run on a fresh defaults domain.
2. Release 0.4.0 (notarized); fill the cask's sha256; publish the Homebrew tap (`millwright-software/homebrew-tap`).
3. Review and publish the page; point its button at 0.4.0.
4. Eric: post the launch drafts when he's ready (his accounts, his voice).

## Not now

Live meeting text, speaker labels inside "Them", languages beyond English, auto-update (Sparkle). In IDEAS.
