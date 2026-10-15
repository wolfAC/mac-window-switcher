# Window Switcher

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

Pushing a `v*` tag runs `.github/workflows/release.yml`: tests, a universal build, and a GitHub Release with a zip and a DMG. To sign releases with your certificate, export it as a `.p12` and add these repository secrets:

- `SIGNING_CERT_P12`: `base64 -i cert.p12 | pbcopy`
- `SIGNING_CERT_PASSWORD`
- `SIGNING_IDENTITY`: e.g. `Window Switcher Dev`

`packaging/window-switcher.rb` is a Homebrew cask template for your own tap.

## License

MIT
