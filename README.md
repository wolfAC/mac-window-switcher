# Window Switcher

[Download](https://github.com/wolfAC/mac-window-switcher/releases/latest) · macOS 14+ · Intel and Apple Silicon

A free, open-source Cmd+Tab replacement for macOS that shows every window, not just app icons.

- Hold **⌘** and press **Tab** to see every window with a live preview, most recently used first.
- Tap ⌘Tab quickly to jump straight back to the previous window, with no overlay flash.
- Release **⌘** to switch. **Esc** cancels.

## Keys while the switcher is open

| Key | Action |
|---|---|
| Tab / Shift+Tab | Next / previous window |
| Arrow keys | Move around the grid |
| Mouse | Hover to select, click to switch |
| W | Close the window |
| M | Minimise the window |
| H | Hide the app |
| Q | Quit the app |
| Esc | Cancel |

Windows on every Space are listed individually, never grouped by app. Finding windows on other Spaces and switching to them uses private macOS APIs (`_AXUIElementCreateWithRemoteToken`, `_AXUIElementGetWindow`, SkyLight); each has a public fallback, and choosing **Current Space only** in Settings avoids the off-Space scan entirely. Previews of windows on other Spaces may show the app icon until you've visited that Space.

The shortcut (⌘, ⌥ or ⌃ + Tab, plus an optional second one), which windows appear, preview size, theme, hold delay and launch at login are all in **Settings…** in the menu bar.

## Install a downloaded release

The app isn't notarized by Apple, so macOS blocks it the first time. Either:

- Open it, then go to System Settings → Privacy & Security → **Open Anyway**, or
- Run `xattr -dr com.apple.quarantine "/Applications/Window Switcher.app"`

## Permissions

On first launch a window walks you through both:

- **Accessibility**: to catch ⌘Tab before macOS does, and to focus, close and minimise windows.
- **Screen Recording**: for window previews. Without it you'll see app icons instead. macOS applies it after a relaunch, and macOS 15 and later may ask you to re-confirm it from time to time.

Nothing is recorded or sent anywhere. If Accessibility is revoked or you choose **Pause** in the menu, the native ⌘Tab works again.

## Build from source

Requires macOS 14+ and Swift 6 (the Xcode Command Line Tools are enough).

    ./scripts/build-app.sh          # universal release build → build/Window Switcher.app
    open "build/Window Switcher.app"

    ./scripts/run-dev.sh            # fast debug build for this Mac, then relaunch
    swift test                      # unit tests (Swift Testing)
    ./scripts/make-dmg.sh           # build/WindowSwitcher.dmg from the built app
    ./scripts/make-icon.sh icon.png # Resources/AppIcon.icns from a 1024 px PNG

Debug logs: `log stream --predicate 'subsystem == "com.wolf.windowswitcher"'`. The menu bar's **Debug → Dump Windows to Log** prints the current window list.

### Keep permissions across rebuilds

An ad-hoc signature changes on every build, so macOS forgets the permissions. Create a self-signed certificate once and sign with it:

1. Keychain Access → Certificate Assistant → Create a Certificate…
2. Name: `Window Switcher Dev`, Identity Type: Self Signed Root, Certificate Type: **Code Signing**.
3. The build scripts pick up a certificate named `Window Switcher Dev` automatically. Any other name: `SIGN_IDENTITY="My Cert" ./scripts/run-dev.sh`.

The certificate doesn't need to be trusted to sign. Never commit it.

## Releases

Download the latest DMG from [Releases](https://github.com/wolfAC/mac-window-switcher/releases).

Releases are built and signed on the maintainer's Mac, so the signing key never goes to GitHub:

    scripts/release.sh 0.2.0

It sets the version in `Info.plist`, commits and tags `v0.2.0`, builds the universal app, makes the zip and DMG, pushes, and uploads them with `gh release create`. It refuses to run without the `Window Switcher Dev` certificate, because every release must be signed with the same one or users lose their permissions. Back the certificate up (Keychain Access → export as `.p12`) and keep it safe.

GitHub Actions runs the tests and a build on every push (`.github/workflows/ci.yml`). `packaging/mac-window-switcher.rb` is a Homebrew cask template for your own tap; `release.sh` prints the version and sha256 to put in it.

## License

MIT
