import AppKit
import SwitcherCore

/// Runs `SwitcherState` and carries out its effects: loading the window list, the hold
/// timer, the overlay, previews and the final focus.
@MainActor
final class SwitcherController: HotkeyTapDelegate {
    private var state = SwitcherState()
    /// Every window in this session, in display order.
    private var allWindows: [WindowInfo] = []
    /// What's on screen: `allWindows` narrowed by `query`. Indices everywhere refer to this.
    private var windows: [WindowInfo] = []
    /// Type-to-filter text.
    private var query = ""
    private var outsideClickMonitor: Any?
    private var session = 0
    private var holdTimer: DispatchWorkItem?
    private var triggeredAt: Date?
    private var screen: NSScreen?

    private let catalog: WindowCatalog
    private let recents: RecentsTracker
    private let thumbnails: ThumbnailService
    private let preferences: Preferences
    private let panel = SwitcherPanel()

    init(catalog: WindowCatalog, recents: RecentsTracker, thumbnails: ThumbnailService, preferences: Preferences) {
        self.catalog = catalog
        self.recents = recents
        self.thumbnails = thumbnails
        self.preferences = preferences

        catalog.onOffSpaceChange = { [weak self] in
            guard let self, self.state.isActive else { return }
            self.loadWindows(session: self.session)
        }
        panel.grid.onHover = { [weak self] index in self?.send(.select(index: index)) }
        panel.grid.onClick = { [weak self] index in self?.send(.click(index: index)) }
        panel.grid.onCommand = { [weak self] index, command in
            guard let self else { return }
            if command == .fullScreen {
                // Switch to it first, then go full screen (both on the same serial AX queue).
                guard index < self.windows.count else { return }
                let window = self.windows[index]
                self.send(.click(index: index))
                WindowActions.perform(.fullScreen, on: window)
                return
            }
            self.send(.select(index: index))
            self.run(command)
        }
    }

    // MARK: HotkeyTapDelegate

    var switcherIsActive: Bool { state.isActive }
    var switcherIsVisible: Bool { state.isVisible }

    func hotkeyTriggered(reverse: Bool) {
        if !state.isActive { triggeredAt = Date() }
        send(.trigger(reverse: reverse))
    }

    func hotkeyModifierReleased() { send(.released) }
    func hotkeyEscape() { send(.escape) }

    func hotkeyArrow(_ keyCode: CGKeyCode) {
        guard let current = state.selection, let layout = panel.grid.layout else { return }
        let direction: GridDirection = switch keyCode {
        case KeyCode.leftArrow: .left
        case KeyCode.rightArrow: .right
        case KeyCode.upArrow: .up
        default: .down
        }
        send(.select(index: layout.neighbor(of: current, direction)))
    }

    func hotkeyCommand(_ command: WindowCommand) {
        run(command)
    }

    func hotkeyType(_ text: String) {
        setQuery(query + text)
    }

    func hotkeyBackspace() {
        guard !query.isEmpty else { return }
        setQuery(String(query.dropLast()))
    }

    func hotkeyConfirm() { send(.confirm) }

    func hotkeyMove(by delta: Int) { send(.move(by: delta)) }

    private func setQuery(_ newQuery: String) {
        guard state.isVisible else { return }
        query = newQuery
        windows = filtered(allWindows)
        Log.switcher.debug("Filter \"\(newQuery, privacy: .private)\" → \(self.windows.count) of \(self.allWindows.count)")
        send(.filtered(count: windows.count))
    }

    private func filtered(_ list: [WindowInfo]) -> [WindowInfo] {
        guard !query.isEmpty else { return list }
        return list.filter { WindowSearch.matches(query, fields: [$0.displayTitle, $0.title, $0.appName]) }
    }

    /// Cancels any open session, e.g. when the tap is paused.
    func reset() {
        if state.isActive { send(.escape) }
    }

    // MARK: State machine

    private func send(_ event: SwitcherEvent) {
        for effect in state.handle(event) {
            apply(effect)
        }
    }

    private func apply(_ effect: SwitcherEffect) {
        switch effect {
        case .loadWindows:
            session += 1
            screen = nil
            loadWindows(session: session, locateScreen: true)

        case .startHoldTimer:
            holdTimer?.cancel()
            let timer = DispatchWorkItem { [weak self] in self?.send(.holdElapsed) }
            holdTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(preferences.holdDelayMs), execute: timer)

        case .show:
            show()

        case .updateSelection(let index):
            panel.grid.select(index)

        case .hide:
            panel.dismiss()
            stopOutsideClickMonitor()

        case .commit(let index):
            endSession()
            guard index < windows.count else { return }
            let target = windows[index]
            recents.touch(target.axElement)
            WindowActions.focus(target)
            Log.switcher.debug("Commit → \(target.appName, privacy: .public)")

        case .cancel:
            endSession()
        }
    }

    private func endSession() {
        holdTimer?.cancel()
        holdTimer = nil
        thumbnails.cancel()
        session += 1
        query = ""
        stopOutsideClickMonitor()
    }

    /// While searching the overlay stays open without the modifier held, and it swallows
    /// every key; a click anywhere else closes it so it can never trap the keyboard.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.escape) }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Called from the event tap's callback, so nothing here may wait on another app:
    /// the frontmost window lookup (AX) runs on `AXQueue` before the catalog snapshot.
    private func loadWindows(session: Int, locateScreen: Bool = false) {
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task {
            let focused = await Self.focusedWindow(of: frontPid)
            guard session == self.session else { return }
            // Make sure the window the user is looking at right now ranks first, even if a
            // notification was missed.
            recents.touchIfPresent(focused?.element)
            if locateScreen { screen = targetScreen(focusedFrame: focused?.frame) }
            let options = WindowFilterOptions(
                includeMinimized: preferences.includeMinimized,
                includeHidden: preferences.includeHidden,
                scope: preferences.scope,
                activeScreenIndex: screen.flatMap { NSScreen.screens.firstIndex(of: $0) }
            )
            let snapshot = await catalog.snapshot(options: options)
            guard session == self.session else { return }
            recents.prune(alive: snapshot.all)
            thumbnails.prune(keeping: Set(snapshot.all.compactMap(\.windowID)))
            let selected = state.selection.flatMap { $0 < windows.count ? windows[$0].axElement : nil }
            let recent = recents.ordered(snapshot.visible).map { window in
                var window = window
                window.customName = preferences.customName(for: window)
                return window
            }
            var previous = 1
            if preferences.groupByApp {
                allWindows = AppGrouping.grouped(recent) { $0.pid }
                if recent.count > 1, let index = allWindows.firstIndex(where: { $0.axElement == recent[1].axElement }) {
                    previous = index
                }
            } else {
                allWindows = recent
            }
            windows = filtered(allWindows)
            // Start captures now, not when the overlay appears: the hold delay gives them a
            // head start, and even a quick tap that never shows the overlay warms the cache.
            refreshThumbnails()
            send(.loaded(count: windows.count, previous: previous))
            // A reload can insert windows; stay on the one that was selected if it's still there.
            if let selected, let index = windows.firstIndex(where: { $0.axElement == selected }) {
                send(.select(index: index))
            }
        }
    }

    private var metrics: GridMetrics {
        GridMetrics(thumbnailHeight: preferences.thumbnailSize.height, titleHeight: preferences.showTitles ? 20 : 0)
    }

    private func show() {
        guard let screen = screen ?? NSScreen.main else { return }
        let metrics = metrics
        startOutsideClickMonitor()
        panel.present(
            windows: windows, query: query, total: allWindows.count, metrics: metrics, showTitles: preferences.showTitles, on: screen,
            appearance: preferences.appearance.nsAppearance, thumbnail: { [thumbnails] in thumbnails.cached($0.windowID) }
        )
        // Only the session's first show: later ones are re-renders (a reload while open).
        if let triggeredAt {
            Log.perf.info("Overlay first frame \(Int(Date().timeIntervalSince(triggeredAt) * 1000)) ms after trigger (\(self.windows.count) windows)")
            self.triggeredAt = nil
        }
    }

    private func refreshThumbnails() {
        let metrics = metrics
        let start = Date()
        thumbnails.refresh(
            windows,
            pointSize: { window in
                CGSize(width: metrics.thumbnailHeight * min(max(window.aspectRatio, metrics.minAspect), metrics.maxAspect), height: metrics.thumbnailHeight)
            },
            onImage: { [weak self] id, image in
                guard let self, self.state.isVisible else { return }
                let indices = self.windows.indices.filter { self.windows[$0].windowID == id }
                self.panel.grid.setThumbnail(image, forWindowAt: indices)
            },
            onFinished: { count in
                Log.perf.info("\(count) previews in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            }
        )
    }

    private struct FocusedWindow: @unchecked Sendable {
        let element: AXUIElement
        let frame: CGRect?
    }

    /// The frontmost app's focused window and its frame, looked up off the main thread.
    private static func focusedWindow(of pid: pid_t?) async -> FocusedWindow? {
        guard let pid else { return nil }
        return await AXQueue.run {
            guard let element = AXUIElement.application(pid).element(kAXFocusedWindowAttribute) else { return nil }
            AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
            return FocusedWindow(element: element, frame: element.frame)
        }
    }

    /// The screen with the active window, or the one under the mouse.
    private func targetScreen(focusedFrame: CGRect?) -> NSScreen? {
        switch preferences.overlayScreen {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        case .activeWindow:
            guard let focusedFrame,
                  let index = WindowCatalog.screenIndex(for: focusedFrame, screens: WindowCatalog.screenFramesInCGSpace()),
                  index < NSScreen.screens.count
            else { return NSScreen.main }
            return NSScreen.screens[index]
        }
    }

    // MARK: Actions while the overlay is open

    private func run(_ command: WindowCommand) {
        guard state.isVisible, let index = state.selection, index < windows.count else { return }
        WindowActions.perform(command, on: windows[index])
        // Give the app a moment to act, then reload the list in place.
        let delay: Int = command == .quit ? 400 : 200
        let current = session
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
            guard let self, self.session == current, self.state.isActive else { return }
            self.loadWindows(session: current)
        }
    }

    // MARK: Debug

    func dumpWindows() {
        Task {
            let snapshot = await catalog.snapshot(options: WindowFilterOptions(includeMinimized: true, includeHidden: true, scope: .all))
            let ordered = recents.ordered(snapshot.visible)
            var lines = ["Window dump: \(ordered.count) shown of \(snapshot.all.count) AX windows"]
            for (index, w) in ordered.enumerated() {
                let flags = [w.isMinimized ? "min" : nil, w.isAppHidden ? "hidden" : nil, w.isOnCurrentSpace ? "space" : nil]
                    .compactMap { $0 }.joined(separator: ",")
                lines.append("\(index). [\(w.windowID.map(String.init) ?? "-")] \(w.appName) — \"\(w.title)\" \(Int(w.frame.width))x\(Int(w.frame.height)) screen=\(w.screenIndex.map(String.init) ?? "-") \(flags)")
            }
            let text = lines.joined(separator: "\n")
            Log.windows.info("\(text, privacy: .public)")
            print(text)
        }
    }
}
