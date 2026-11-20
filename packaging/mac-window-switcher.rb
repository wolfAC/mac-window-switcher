# Homebrew cask for your own tap (e.g. github.com/<you>/homebrew-tap, file Casks/mac-window-switcher.rb).
# Update version + sha256 for each release (scripts/release.sh prints both):
#   shasum -a 256 build/WindowSwitcher.zip
cask "mac-window-switcher" do
  version "0.3.2"
  sha256 "b988b97e71989394798322955bb72affa5f0065b0ce246722070e60610a7d29c"

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
