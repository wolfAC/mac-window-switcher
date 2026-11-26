# Homebrew cask for your own tap (e.g. github.com/<you>/homebrew-tap, file Casks/mac-window-switcher.rb).
# Update version + sha256 for each release (scripts/release.sh prints both):
#   shasum -a 256 build/WindowSwitcher.zip
cask "mac-window-switcher" do
  version "0.3.3"
  sha256 "1ddbe8158b9f3fe92fe2e66f491ff1f6a2d5ade1c0a8f113ebc6a31fadb13c7e"

  url "https://github.com/wolfAC/mac-window-switcher/releases/download/v#{version}/WindowSwitcher.zip"
  name "Window Switcher"
  desc "Cmd+Tab replacement that shows every window"
  homepage "https://github.com/wolfAC/mac-window-switcher"

  # The app updates itself from GitHub Releases, so `brew upgrade` leaves it alone.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Window Switcher.app"

  # Not notarized: remove the quarantine flag so Gatekeeper doesn't block it.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Window Switcher.app"]
  end

  zap trash: "~/Library/Preferences/com.wolf.windowswitcher.plist"
end
