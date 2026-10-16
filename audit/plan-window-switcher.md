# Plan: Window Switcher — a free, open-source Cmd+Tab replacement for macOS

## Context
macOS's Cmd+Tab shows one icon per app. You want a switcher that shows **every window** with a live preview, like AltTab. The app should be free, open source, and distributed without a paid Apple Developer account.

**Current state (2026-10-10):**
- The project is at `~/Workspace/Personal/Projects/mac-window-switcher`.
- It's a Swift Package that builds a universal (Intel + Apple Silicon) `.app` with `scripts/build-app.sh`, using only the Xcode Command Line Tools.
- It runs as a menu bar app with no Dock icon. The menu has a Quit item and nothing else yet.
- The dev Mac runs macOS 15.8.1 (Intel) with Swift 6.1.2. Its toolchain includes **Swift Testing** but not XCTest, so tests use `import Testing`.

**Goals for v1.0:**
1. Holding Cmd and pressing Tab shows an overlay of every window, with previews, ordered by most recently used.
2. Releasing Cmd switches to the selected window, and it feels at least as fast as the native switcher.
3. It's free to build, free to download, and installs with a short guide.

**Non-goals for v1.0:** App Store release, Windows/Linux support, and window tiling or management beyond close, minimise and quit.

---

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Language / UI | Swift 6, AppKit for the overlay and hotkey; SwiftUI only for the Settings window | AppKit gives precise control over a non-activating floating panel. SwiftUI is quicker for forms. |
| Build system | Swift Package Manager + `scripts/build-app.sh` (no Xcode project) | Works with the free Command Line Tools, and diffs are clean. |
| Minimum macOS | **Raise from 13 to 14 (Sonoma)** | `SCScreenshotManager` (one-call window capture) needs 14. The older `CGWindowListCreateImage` is deprecated in 14 and removed in 15. |
| Hotkey capture | `CGEventTap` | It's the only public way to intercept Cmd+Tab before macOS's own switcher. Requires Accessibility permission. |
| Window list | Accessibility API (`AXUIElement`) for each app, combined with `CGWindowListCopyWindowInfo` | AX gives titles, minimised state and control over windows. CG gives window IDs, bounds and layer. |
| Previews | ScreenCaptureKit (`SCScreenshotManager`) | The supported modern API. Requires Screen Recording permission. |
| Private APIs | Avoid in v1.0. Allow later only behind a setting, for Spaces support. | They can break with any macOS update. Matching AX windows to CG IDs needs `_AXUIElementGetWindow` (private); fall back to matching by title and bounds. |
| Tests | Swift Testing (`swift test`) on pure logic | XCTest isn't in the Command Line Tools. |
| License | **MIT** (or GPL-3.0 if you want to reuse AltTab code) | AltTab is GPL-3.0. Copying its code means this project must also be GPL. Reading it for ideas is fine. |
| Signing | Ad-hoc during development, then a **self-signed certificate** for releases | Free. A stable signature keeps users' permissions across updates. |
| Updates | Sparkle 2 (EdDSA-signed appcast on GitHub Pages) | Free, the standard for apps outside the App Store, and needs no Apple account. |

---

## Architecture

```
Sources/WindowSwitcher/
├── App/
│   ├── main.swift               # NSApplication bootstrap, .accessory policy
│   ├── AppDelegate.swift        # wires services together, menu bar item
│   └── StatusMenu.swift         # menu: Settings…, Pause, About, Quit
├── Permissions/
│   ├── PermissionsService.swift # AXIsProcessTrusted, CGPreflightScreenCaptureAccess, open System Settings panes
│   └── OnboardingWindow.swift   # first-run screen that walks through both permissions
├── Input/
│   ├── HotkeyTap.swift          # CGEventTap: Cmd+Tab down → show/next, Cmd up → commit, Esc → cancel
│   └── KeyBinding.swift         # configurable modifier + key (Cmd/Option + Tab, etc.)
├── Windows/
│   ├── WindowInfo.swift         # model: id, pid, app name/icon, title, bounds, isMinimized, isHidden, screen
│   ├── WindowCatalog.swift      # builds the window list (AX + CG), filters junk windows
│   ├── RecentsTracker.swift     # MRU order via NSWorkspace activation + AX focused-window notifications
│   └── WindowActions.swift      # focus / raise / close / minimize / quit app (AX actions)
├── Thumbnails/
│   └── ThumbnailService.swift   # ScreenCaptureKit capture, cache, downscale, refresh policy
├── Switcher/
│   ├── SwitcherController.swift # state machine: idle → armed → visible → committing/cancelled
│   ├── SwitcherPanel.swift      # non-activating NSPanel on the active screen, all Spaces
│   └── SwitcherGridView.swift   # layout of window cells, selection highlight, hover/click
├── Settings/
│   ├── Preferences.swift        # typed UserDefaults wrapper
│   └── SettingsView.swift       # SwiftUI settings window
└── Support/
    └── Log.swift                # os.Logger categories

Tests/WindowSwitcherTests/       # Swift Testing: selection logic, MRU, filtering, layout math
```

**How a Cmd+Tab press flows:**
1. `HotkeyTap` sees Tab pressed while Cmd is held. It **swallows** the event so the native switcher never appears, then tells `SwitcherController` to "advance".
2. On the first press, the controller takes a list snapshot from `WindowCatalog`, ordered by `RecentsTracker`, and selects index 1 (the previous window).
3. If Cmd is still held after about **120 ms**, the panel appears. A quick tap-and-release switches straight to the previous window without flashing the overlay, matching the native behaviour.
4. Each further Tab moves the selection forward and Shift+Tab moves it back. Thumbnails stream into their cells as `ThumbnailService` captures them, so app icons show until a preview is ready.
5. Releasing Cmd makes `WindowActions` focus the selected window and hide the panel. Pressing Esc cancels.

---

## Phases

Each phase ends with something you can run. The checkboxes are the acceptance criteria.

### Phase 0: Foundation (done, plus cleanup)
- [x] Swift package, universal build script, ad-hoc signing, menu bar app.
- [ ] Raise the minimum to macOS 14 in `Package.swift` and `Info.plist`.
- [ ] Restructure into the folder layout above. Add `Log.swift`.
- [ ] Add a `Tests/` target and confirm `swift test` runs with Swift Testing.
- [ ] Add `scripts/run-dev.sh` to build the debug version, kill the running app, and relaunch it, so iteration is fast.
- [ ] First commit.

### Phase 1: Permissions and onboarding
- [ ] `PermissionsService` checks Accessibility (`AXIsProcessTrustedWithOptions`) and Screen Recording (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`).
- [ ] A first-run window explains why each permission is needed, has buttons that open the exact System Settings pane, and updates live once a permission is granted.
- [ ] The menu bar shows a warning badge if either permission is missing.
- **Known macOS quirk:** an ad-hoc signed build changes signature on every rebuild, so macOS forgets the permissions. During development, either re-grant after each build or sign with the self-signed certificate from Phase 7 early.

### Phase 2: Window catalog and recents
- [ ] List every normal window in every regular app (`NSRunningApplication.activationPolicy == .regular`).
- [ ] Filter out junk windows: zero-size, non-standard subroles (`AXStandardWindow` only), off-layer, and the app's own panel.
- [ ] Include minimised windows (shown with an icon, since they can't be captured) and windows of hidden apps. Each type gets its own setting.
- [ ] `RecentsTracker` keeps an MRU order across app activations **and** window focus changes inside one app (AX `kAXFocusedWindowChangedNotification` observers, added and removed as apps launch and quit).
- [ ] Add a debug menu item, "Dump windows", that logs the current list, for checking it against reality.
- [ ] Unit tests: filtering rules and MRU ordering, using fake window data.

### Phase 3: Hotkey interception
- [ ] A `CGEventTap` on `keyDown`, `keyUp` and `flagsChanged` captures Cmd+Tab, Cmd+Shift+Tab, Cmd+` (same-app windows, later), Esc, arrow keys, and Cmd release.
- [ ] Swallow only the events the switcher handles. Everything else passes through untouched.
- [ ] Re-enable the tap if macOS disables it (`tapDisabledByTimeout` / `tapDisabledByUserInput`). Keep the callback fast and do the work on the main queue.
- [ ] A "Pause" menu item turns the tap off so the native Cmd+Tab works again.
- [ ] **Edge cases:**
  - Secure input mode (password fields) blocks event taps. The native switcher still works there, so nothing breaks.
  - Keep the native switcher working whenever the tap is off or Accessibility permission is revoked.
- [ ] Unit tests: the `SwitcherController` state machine (tap vs hold, Tab/Shift+Tab wrap-around, cancel).

### Phase 4: Switcher overlay
- [ ] An `NSPanel` with `.nonactivatingPanel`, `.borderless`, level `.popUpMenu`, and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`. It must never steal focus from the current app.
- [ ] Appears centred on the screen that has the active window (or the mouse; this becomes a setting).
- [ ] Grid layout: cells sized from the window's aspect ratio, wrapping into rows, with a maximum width of about 90% of the screen. Long lists scroll.
- [ ] Each cell shows a thumbnail (or the app icon as a placeholder), a small app icon badge, and the window title (truncated).
- [ ] Selection highlight. Hovering moves the selection, and clicking commits it.
- [ ] Uses a vibrancy (frosted glass) background and follows light/dark mode.
- [ ] Unit tests: the layout calculation (rows and cell sizes for N windows on a given screen size).

### Phase 5: Window previews
- [ ] `ThumbnailService` maps `CGWindowID` to `SCWindow` (from `SCShareableContent`) and calls `SCScreenshotManager.captureImage`, downscaled to about 2× the cell size.
- [ ] Captures run in parallel, and each cell updates as its image arrives. A missing preview never blocks the overlay.
- [ ] Cache: keep the last preview per window and refresh it each time the overlay opens. Discard entries when windows close.
- [ ] Minimised windows and windows on other Spaces fall back to the app icon. (Live capture of other Spaces isn't possible with public APIs.)
- [ ] **Performance target:** the first frame of the overlay appears within 50 ms of the 120 ms hold delay, and every preview arrives within 300 ms for 20 windows.

### Phase 6: Actions and settings
- [ ] Committing a selection runs `NSRunningApplication.activate()`, then AX `kAXRaiseAction` and sets `kAXMainAttribute` on the window. Minimised windows are restored first (`kAXMinimizedAttribute = false`).
- [ ] Keys that work while the overlay is open: `W` closes the window, `M` minimises it, `Q` quits the app, and `H` hides it. Mouse buttons for the same actions appear on hover.
- [ ] A Settings window (SwiftUI) with:
  - **Shortcut:** Cmd+Tab or Option+Tab, plus an optional second shortcut.
  - **Which windows to show:** all, current Space only, current screen only, include minimised, include hidden.
  - **Appearance:** thumbnail size, show titles, light/dark/auto.
  - **Behaviour:** the hold delay, and which screen the overlay appears on.
  - **Launch at login:** via `SMAppService.mainApp` (macOS 13 and later; free, no helper app needed).
- [ ] Preferences live in `UserDefaults`, and changes take effect without a restart.

### Phase 7: Packaging and free distribution
- [ ] **Self-signed certificate:** create it in Keychain Access → Certificate Assistant → Create a Certificate (type: Code Signing). Sign every release with `SIGN_IDENTITY="Window Switcher Dev" ./scripts/build-app.sh`. Never commit the certificate.
- [ ] An app icon (`Resources/AppIcon.icns`, generated from one 1024 px PNG with `iconutil`).
- [ ] `scripts/make-dmg.sh`: `hdiutil create` a DMG containing the app and an Applications shortcut.
- [ ] GitHub repo (public). A GitHub Actions workflow on a `macos` runner builds, tests, and attaches the zip and DMG to a Release when a `v*` tag is pushed. Actions are free for public repos.
- [ ] README: screenshots, the install steps for "Open Anyway" / `xattr`, the permissions guide, and how to build from source.
- [ ] **Homebrew:** publish through your own tap (`brew install --cask wolf/tap/mac-window-switcher`). The main `homebrew/cask` repo is phasing out apps that aren't notarized, so don't rely on it.
- [ ] **Signing secret in CI:** the self-signed certificate's `.p12` goes in a GitHub Actions secret and is imported into a temporary keychain during the build.

### Phase 8: Auto-update
- [ ] Add Sparkle 2 through SwiftPM. Generate an EdDSA key pair with `generate_keys`. The private key stays in a CI secret, and the public key goes in `Info.plist` as `SUPublicEDKey`.
- [ ] `appcast.xml` is hosted on GitHub Pages, and CI updates it on each release.
- [ ] Add a "Check for Updates…" menu item and a daily automatic check (can be turned off).

### Phase 9: Polish and v1.0
- [ ] Multiple displays: the overlay appears on the correct screen, and window cells can show which screen each window is on.
- [ ] Accessibility: VoiceOver labels on the cells, and the panel respects Reduce Motion and Reduce Transparency.
- [ ] Localisation-ready strings (English only at launch).
- [ ] Crash and edge-case pass:
  - apps with dozens of windows
  - apps that freeze (AX calls need timeouts: `AXUIElementSetMessagingTimeout` ~0.25 s)
  - full-screen apps
  - Stage Manager
- [ ] Tag v1.0.0, release it, and post it to Show HN / r/macapps.

### Later (after v1.0)
- Windows on other Spaces, using private CGS/SkyLight APIs behind an "experimental" setting.
- Cmd+` to switch between windows of the same app only.
- Search: start typing while the overlay is open to filter by app or window title.
- Themes, a list-style layout (no previews) for low-power use, and per-app blacklist.

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| macOS updates break the event tap or AX behaviour | The switcher stops working | Fail safe: if the tap dies, the native Cmd+Tab still works. Test on each macOS beta. |
| Users lose permissions after updates | Annoying re-grant prompts | Sign every release with the same self-signed certificate. |
| macOS 15+ asks users to re-confirm Screen Recording periodically | A recurring system prompt | Document it in the README. Previews fall back to icons while permission is missing. |
| Gatekeeper warning scares users away | Fewer installs | A clear install guide with screenshots, an open-source build-it-yourself option, and a Homebrew tap. |
| Slow previews with many windows | The overlay feels laggy | Show icons immediately, capture asynchronously, cache, and downscale. |
| Unresponsive apps block AX calls | The overlay freezes | Set AX messaging timeouts and run AX queries off the main thread. |

---

## Verification
- **Automated:** `swift test` runs the logic tests (filtering, MRU, state machine, layout) in CI on every push.
- **Manual checklist, run before each release:**
  - Fresh install on a clean user account: Gatekeeper bypass, onboarding, granting both permissions.
  - Tap Cmd+Tab: switches to the previous window with no overlay flash.
  - Hold Cmd+Tab: the overlay shows every window. Tab, Shift+Tab, arrows and mouse all select. Releasing focuses the right window.
  - Esc cancels. W, M, Q and H work.
  - Minimised and hidden windows behave as configured.
  - Two displays and a full-screen app.
  - Pause works, and revoking Accessibility restores the native switcher.
  - Updating from the previous release keeps permissions (self-signed certificate) and Sparkle offers the update.
- **Performance:** log the time from hotkey to the overlay's first frame, and to the last preview arriving, with 20+ windows open.

## Milestones
| Milestone | Phases | Result |
|---|---|---|
| M1: "It switches" | 0–3 + a basic Phase 4 (icons only) | Usable daily with Cmd+Tab and no previews |
| M2: "It looks right" | 4–5 | Previews, polished overlay |
| M3: "Ready to share" | 6–7 | Settings, signed DMG on GitHub Releases |
| M4: v1.0 | 8–9 | Auto-update, multi-display, accessibility, public launch |
