# Source of truth for Casks/notchbox.rb in herval/homebrew-tap.
# Scripts/render-cask.sh supplies the release version and archive checksum.
cask "notchbox" do
  version "0.1.5"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/herval/notchbox/releases/download/v#{version}/notchbox_#{version}_universal.zip"
  name "Notchbox"
  desc "Terminal tucked into the display notch"
  homepage "https://github.com/herval/notchbox"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Notchbox.app"

  uninstall quit: "dev.littleguys.notchbox"

  zap trash: [
    "~/Library/Preferences/dev.littleguys.notchbox.plist",
    "~/Library/Saved Application State/dev.littleguys.notchbox.savedState",
  ]
end
