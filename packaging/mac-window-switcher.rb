# Homebrew cask for your own tap (e.g. github.com/<you>/homebrew-tap, file Casks/mac-window-switcher.rb).
# Update version + sha256 for each release (scripts/release.sh prints both):
#   shasum -a 256 build/WindowSwitcher.zip
cask "mac-window-switcher" do
  version "0.2.0"
  sha256 "a25e76529cfabcd454f476d02488e1323072794ac900aad13064ee391a6dae7b"

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
