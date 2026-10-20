import AppKit
import SwitcherCore

/// Builds the window list from AX (titles, minimised state, control) joined with
/// CGWindowList (window IDs, layer, which windows are on the current Space).
///
/// AX → CG matching uses the private `_AXUIElementGetWindow`, falling back to pid + bounds
/// (+ title as a tie-break). Windows on other Spaces come from `OffSpaceWindowCache`, which
/// remembers every window seen on any Space and fills gaps with a brute-force scan.
@MainActor
final class WindowCatalog {
    private let offSpace = OffSpaceWindowCache()
    private var watchTokens: [NSObjectProtocol] = []

    /// Called when a background scan changes the known windows on other Spaces, so an open
    /// switcher can reload instead of showing a list that's missing them until the next ⌘Tab.
    var onOffSpaceChange: (() -> Void)? {
        didSet { offSpace.onChange = { [weak self] in self?.onOffSpaceChange?() } }
    }

    struct Snapshot {
        /// Everything AX reported, before filtering. Used to prune the recents list.
        var all: [WindowInfo]
        var visible: [WindowInfo]
    }

    // Plain values handed to the background queue. NSImage and AXUIElement are immutable here.
    private struct AppRef: @unchecked Sendable {
        let pid: pid_t
        let name: String
        let icon: NSImage?
        let isHidden: Bool
    }

    private struct CGEntry: Sendable {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        let title: String?
    }

    private let queue = DispatchQueue(label: "WindowCatalog", qos: .userInteractive, attributes: .concurrent)

    func snapshot(options: WindowFilterOptions) async -> Snapshot {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPid }
            .map { AppRef(pid: $0.processIdentifier, name: $0.localizedName ?? "", icon: $0.icon, isHidden: $0.isHidden) }
        let screens = Self.screenFramesInCGSpace()
        let cache = options.scope == .currentSpace ? nil : offSpace

        let start = Date()
        let all: [RawWindow] = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.collect(apps: apps, screens: screens, offSpace: cache))
            }
        }
        let visible = all.filter { raw in
            let w = raw.window
            return WindowFilter.shouldShow(
                WindowCandidate(
                    subrole: raw.subrole, size: w.frame.size, layer: raw.layer,
                    isMinimized: w.isMinimized, isAppHidden: w.isAppHidden, isOwnProcess: false,
                    isOnCurrentSpace: w.isOnCurrentSpace, screenIndex: w.screenIndex
                ),
                options: options
            )
        }.map(\.window)
        Log.perf.debug("Catalog: \(all.count) AX windows, \(visible.count) shown, \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        return Snapshot(all: all.map(\.window), visible: visible)
    }

    /// Keeps the other-Spaces cache fresh: records the windows on each Space as it's visited
    /// and each app's windows as it activates, plus a full scan now, on every Space change and
    /// for each newly launched app. All of it runs in the background, off the ⌘Tab path.
    func startWatchingSpaces() {
        guard watchTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        watchTokens = [
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scanAllApps() }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [offSpace] note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                offSpace.recordCurrentSpace([pid])
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [offSpace] note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                // Give the app time to open its windows.
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { offSpace.scan([pid], force: true) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [offSpace] note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                offSpace.forget(pid)
            },
        ]
        scanAllApps()
    }

    private func scanAllApps() {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPid }
            .map(\.processIdentifier)
        offSpace.recordCurrentSpace(pids)
        offSpace.scan(pids, force: true)
    }

    /// NSScreen frames converted to CG global space (top-left origin of the primary screen).
    static func screenFramesInCGSpace() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { screen in
            let f = screen.frame
            return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        }
    }

    nonisolated static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    // MARK: - Background work

    private struct RawWindow: @unchecked Sendable {
        let window: WindowInfo
        let subrole: String?
        let layer: Int?
    }

    private nonisolated static func collect(apps: [AppRef], screens: [CGRect], offSpace: OffSpaceWindowCache?) -> [RawWindow] {
        let cgAll = cgWindows(onScreenOnly: false)
        let onScreenIDs = Set(cgWindows(onScreenOnly: true).map(\.id))
        let cgByPid = Dictionary(grouping: cgAll, by: \.pid)

        // AX queries are independent per app and can each wait on a slow app, so run them in parallel.
        var perApp = [[RawWindow]](repeating: [], count: apps.count)
        var needsScan: [pid_t] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let (windows, missing) = windowsOf(
                app, cgCandidates: cgByPid[app.pid] ?? [], onScreenIDs: onScreenIDs, screens: screens,
                offSpace: offSpace
            )
            lock.lock()
            perApp[index] = windows
            if missing { needsScan.append(app.pid) }
            lock.unlock()
        }
        // CG knows about windows (e.g. one just opened on another Space) that AX didn't give us.
        // Rescan those apps in the background so they show up next time.
        if let offSpace, !needsScan.isEmpty { offSpace.scan(needsScan) }

        // One global front-to-back order across all apps, so windows are never grouped by app.
        // RecentsTracker refines this into MRU order.
        let zOrder = Dictionary(uniqueKeysWithValues: cgAll.enumerated().map { ($1.id, $0) })
        return perApp.flatMap { $0 }.sorted { a, b in
            (a.window.windowID.flatMap { zOrder[$0] } ?? .max) < (b.window.windowID.flatMap { zOrder[$0] } ?? .max)
        }
    }

    /// - Returns: the app's windows, and whether CG lists a normal window we couldn't find in AX.
    private nonisolated static func windowsOf(
        _ app: AppRef, cgCandidates: [CGEntry], onScreenIDs: Set<CGWindowID>, screens: [CGRect], offSpace: OffSpaceWindowCache?
    ) -> ([RawWindow], Bool) {
        let appElement = AXUIElement.application(app.pid)
        let currentSpaceWindows = appElement.elements(kAXWindowsAttribute)
        var unmatched = cgCandidates.filter { $0.layer == 0 }
        var result: [RawWindow] = []
        var seenIDs = Set<CGWindowID>()
        var seenElements = Set<AXUIElement>()
        var toRemember: [AXUIElement] = []
        var closed: [AXUIElement] = []
        defer {
            offSpace?.remember(toRemember, of: app.pid)
            offSpace?.drop(closed, of: app.pid)
        }

        for element in currentSpaceWindows + (offSpace?.windows(of: app.pid) ?? []) {
            guard seenElements.insert(element).inserted else { continue }
            AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
            guard let frame = element.frame else {
                if !element.isAlive { closed.append(element) }
                continue
            }
            let title = element.string(kAXTitleAttribute) ?? ""
            let subrole = element.string(kAXSubroleAttribute)
            if subrole == kAXStandardWindowSubrole, currentSpaceWindows.contains(element) {
                toRemember.append(element)
            }
            let minimized = element.bool(kAXMinimizedAttribute) ?? false

            let match: CGEntry?
            if let id = PrivateAX.windowID(of: element) {
                guard seenIDs.insert(id).inserted else { continue } // same window from both sources
                match = cgCandidates.first { $0.id == id }
                unmatched.removeAll { $0.id == id }
            } else {
                let matches = unmatched.enumerated().filter { boundsMatch($0.element.bounds, frame) }
                let best = matches.first { $0.element.title == title } ?? matches.first
                if let best { unmatched.remove(at: best.offset) }
                match = best?.element
                if let id = match?.id, !seenIDs.insert(id).inserted { continue }
            }

            let info = WindowInfo(
                axElement: element,
                windowID: match?.id,
                pid: app.pid,
                appName: app.name,
                appIcon: app.icon,
                title: title,
                frame: frame,
                isMinimized: minimized,
                isAppHidden: app.isHidden,
                isOnCurrentSpace: match.map { onScreenIDs.contains($0.id) } ?? false,
                screenIndex: screenIndex(for: frame, screens: screens)
            )
            result.append(RawWindow(window: info, subrole: subrole, layer: match?.layer))
        }

        let missing = unmatched.contains { entry in
            !onScreenIDs.contains(entry.id)
                && entry.bounds.width >= WindowFilter.minimumSide && entry.bounds.height >= WindowFilter.minimumSide
        }
        return (result, missing)
    }

    private nonisolated static func boundsMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    private nonisolated static func cgWindows(onScreenOnly: Bool) -> [CGEntry] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return CGEntry(id: id, pid: pid, layer: layer, bounds: bounds, title: entry[kCGWindowName as String] as? String)
        }
    }
}

/// AX elements for windows on other Spaces, found by `PrivateAX.allWindows`. That scan
/// costs one AX round trip per candidate ID, so it runs in the background and is cached.
final class OffSpaceWindowCache: @unchecked Sendable {
    private let lock = NSLock()
    private var byPid: [pid_t: [AXUIElement]] = [:]
    private var scanning = Set<pid_t>()
    /// Apps asked for while their scan was running; scanned again as soon as it ends,
    /// so a window opened mid-scan isn't missed.
    private var pending = Set<pid_t>()
    /// Don't rescan an app more than this often when CG keeps reporting a window AX can't see
    /// (e.g. a window type we filter out).
    private var lastScan: [pid_t: Date] = [:]
    private let minimumInterval: TimeInterval = 5
    private let queue = DispatchQueue(label: "OffSpaceWindowCache", qos: .utility)

    /// Called on the main queue when a scan finds windows the cache didn't have, or drops closed ones.
    var onChange: (@MainActor () -> Void)?

    func windows(of pid: pid_t) -> [AXUIElement] {
        lock.withLock { byPid[pid] ?? [] }
    }

    func forget(_ pid: pid_t) {
        lock.withLock {
            byPid[pid] = nil
            lastScan[pid] = nil
            pending.remove(pid)
        }
    }

    /// Adds windows seen in an app's own window list. An AX element stays valid after its
    /// window leaves the Space, so this keeps it reachable from other Spaces even when the
    /// brute-force scan can't find it (apps like Chrome have element IDs beyond its range).
    func remember(_ elements: [AXUIElement], of pid: pid_t) {
        guard !elements.isEmpty else { return }
        lock.withLock {
            let known = byPid[pid] ?? []
            byPid[pid] = known + elements.filter { !known.contains($0) }
        }
    }

    /// Removes windows that have closed.
    func drop(_ elements: [AXUIElement], of pid: pid_t) {
        guard !elements.isEmpty else { return }
        lock.withLock { byPid[pid]?.removeAll { elements.contains($0) } }
    }

    /// Remembers the standard windows each app has on the current Space, in the background.
    func recordCurrentSpace(_ pids: [pid_t]) {
        DispatchQueue.global(qos: .utility).async { [self] in
            DispatchQueue.concurrentPerform(iterations: pids.count) { index in
                let windows = AXUIElement.application(pids[index]).elements(kAXWindowsAttribute).filter { window in
                    AXUIElementSetMessagingTimeout(window, axMessagingTimeout)
                    return window.string(kAXSubroleAttribute) == kAXStandardWindowSubrole
                }
                remember(windows, of: pids[index])
            }
        }
    }

    /// `force` skips the rate limit; use it when windows are likely to have changed (Space switch, launch).
    func scan(_ pids: [pid_t], force: Bool = false) {
        let now = Date()
        let todo: [pid_t] = lock.withLock {
            let due = pids.filter { pid in
                if scanning.contains(pid) {
                    if force { pending.insert(pid) }
                    return false
                }
                return force || now.timeIntervalSince(lastScan[pid] ?? .distantPast) > minimumInterval
            }
            scanning.formUnion(due)
            return due
        }
        guard !todo.isEmpty else { return }
        queue.async { [self] in
            let start = Date()
            let before = todo.map { windows(of: $0) }
            var results = [[AXUIElement]](repeating: [], count: todo.count)
            let resultsLock = NSLock()
            DispatchQueue.concurrentPerform(iterations: todo.count) { index in
                let found = PrivateAX.allWindows(of: todo[index])
                // Keep earlier finds the scan missed (remembered windows it can't reach, or a
                // busy app timing out on some IDs) unless the window is gone.
                let kept = before[index].filter { !found.contains($0) && $0.isAlive }
                resultsLock.withLock { results[index] = found + kept }
            }
            let (changed, again): (Bool, [pid_t]) = lock.withLock {
                var changed = false
                for (index, pid) in todo.enumerated() {
                    // Windows remembered while the scan ran.
                    let added = (byPid[pid] ?? []).filter { !before[index].contains($0) && !results[index].contains($0) }
                    let windows = results[index] + added
                    if Set(byPid[pid] ?? []) != Set(windows) { changed = true }
                    byPid[pid] = windows
                    lastScan[pid] = Date()
                    scanning.remove(pid)
                }
                let again = todo.filter { pending.remove($0) != nil }
                return (changed, again)
            }
            Log.perf.debug("Scanned \(todo.count) apps for windows on other Spaces in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            if !again.isEmpty { scan(again, force: true) }
            if changed, let onChange {
                DispatchQueue.main.async { MainActor.assumeIsolated { onChange() } }
            }
        }
    }
}
