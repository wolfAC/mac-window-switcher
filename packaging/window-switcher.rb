# Homebrew cask for your own tap (e.g. github.com/<you>/homebrew-tap, file Casks/window-switcher.rb).
# Fill in the GitHub owner, then update version + sha256 for each release:
#   shasum -a 256 build/WindowSwitcher.zip
cask "window-switcher" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/OWNER/window-switcher/releases/download/v#{version}/WindowSwitcher.zip"
  name "Window Switcher"
  desc "Cmd+Tab replacement that shows every window"
  homepage "https://github.com/OWNER/window-switcher"

  depends_on macos: ">= :sonoma"

  app "Window Switcher.app"

  # Not notarized: remove the quarantine flag so Gatekeeper doesn't block it.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Window Switcher.app"]
  end

  zap trash: "~/Library/Preferences/com.wolf.windowswitcher.plist"
end
