cask "quill" do
  version "0.4.0"
  sha256 "REPLACE_AT_RELEASE"

  url "https://github.com/millwright-software/quill/releases/download/v#{version}/Quill.zip"
  name "Quill"
  desc "Hold-to-talk dictation and meeting recorder, on-device"
  homepage "https://millwrightsoftware.com/quill/"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Quill.app"

  uninstall quit: "com.millwright.quill"

  zap trash: [
    "~/Library/Application Support/FluidAudio",
    "~/Library/Application Support/Quill",
    "~/Library/Logs/Quill.log",
    "~/Library/Preferences/com.millwright.quill.plist",
  ]
end
