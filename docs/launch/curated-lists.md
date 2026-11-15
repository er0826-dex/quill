# Curated list pull requests (drafts, 11/15)

One PR per list, each from a fork. Descriptions follow each list's own style; all three end with a full stop.
Open them only once the README has the screen clip (lists check that the README is clear, and a
missing image looks abandoned).

---

## 1. jaywcjlove/awesome-mac (≈118k stars, very active, ~2,100 open PRs: expect a wait)

File: `README.md`, section `## Voice-to-Text`, alphabetical: between **Presspeech** and **Spokenly**.

Line:

* [Quill](https://millwrightsoftware.com/quill/) - Hold a key, talk, and the text appears at your cursor in any app, with the words shown live beside the cursor as you speak; also records meetings (your mic plus the Mac's audio) into a Me/Them transcript. Fully on-device with Parakeet. [![Open-Source Software][OSS Icon]](https://github.com/millwright-software/quill) ![Freeware][Freeware Icon]

PR title: Add Quill to Voice-to-Text

PR body:

Quill is a free, open-source (MIT) menu-bar app for macOS 15+ on Apple Silicon. Hold a key and talk; the text is pasted at your cursor about a tenth of a second after you let go, and the words stream beside the cursor while you speak. If another window takes focus before the paste, it holds the text instead of pasting into the wrong app. It also records meetings (mic and system audio as separate tracks) and transcribes them locally into a Me/Them transcript. Everything runs on-device (NVIDIA Parakeet via FluidAudio; Whisper optional for meetings). Notarized release, Homebrew cask: `brew install --cask millwright-software/tap/quill`.

---

## 2. serhii-londar/open-source-mac-os-apps (≈51k stars)

Edit `applications.json` (not the README); one object, categories `audio` and `menubar`. Their rules: recent commits, a clear English README, a license (all true).

```json
{
  "title": "Quill",
  "short_description": "Hold-to-talk dictation that pastes at the cursor in any app and records meetings into a Me/Them transcript, fully on-device.",
  "categories": [
    "audio",
    "menubar"
  ],
  "repo_url": "https://github.com/millwright-software/quill",
  "icon_url": "https://millwrightsoftware.com/quill/icon.png",
  "screenshots": [],
  "official_site": "https://millwrightsoftware.com/quill/",
  "languages": [
    "swift"
  ]
}
```

PR title: Add Quill

PR body: the same paragraph as above. (Add a screenshot URL to `screenshots` once the README clip exists; a still frame of the bubble.)

---

## 3. iCHAIT/awesome-macOS (≈19k stars, ~26 open PRs: the quickest to be read)

File: `README.md`, section `### Audio`, alphabetical: between **Plug** and **Recordia**. Their rules: OSS and Freeware symbols, primary link to the project's site, no Electron (Quill is native Swift), no LLM wrappers (Quill runs local speech models, not an LLM).

Line:

- [Quill](https://millwrightsoftware.com/quill/) - Hold-to-talk dictation that pastes at the cursor in any app, shows the words live as you speak, and records meetings into a transcript, all on-device. [![Open-Source Software][OSS Icon]](https://github.com/millwright-software/quill) ![Freeware][Freeware Icon]

PR title: Add Quill

PR body: the same paragraph as above.
