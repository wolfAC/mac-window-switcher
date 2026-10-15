import AppKit
import SwitcherCore

/// Builds the window list from AX (titles, minimised state, control) joined with
/// CGWindowList (window IDs, layer, which windows are on the current Space).
///
/// AX → CG matching uses the private `_AXUIElementGetWindow`, falling back to pid + bounds
/// (+ title as a tie-break). Windows on other Spaces come from `OffSpaceWindowCache`.
@MainActor
final class WindowCatalog {
    private let offSpace = OffSpaceWindowCache()
    private var watchTokens: [NSObjectProtocol] = []

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

    /// Keeps the other-Spaces cache fresh: a full scan now, on every Space change, and for
    /// each newly launched app. Scans run in the background, off the ⌘Tab path.
    func startWatchingSpaces() {
        guard watchTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        watchTokens = [
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scanAllApps() }
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [offSpace] note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                // Give the app time to open its windows.
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { offSpace.scan([pid]) }
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
        offSpace.scan(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPid }
            .map(\.processIdentifier))
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
                offSpaceWindows: offSpace?.windows(of: app.pid) ?? []
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
        _ app: AppRef, cgCandidates: [CGEntry], onScreenIDs: Set<CGWindowID>, screens: [CGRect], offSpaceWindows: [AXUIElement]
    ) -> ([RawWindow], Bool) {
        let appElement = AXUIElement.application(app.pid)
        var unmatched = cgCandidates.filter { $0.layer == 0 }
        var result: [RawWindow] = []
        var seenIDs = Set<CGWindowID>()
        var seenElements = Set<AXUIElement>()

        for element in appElement.elements(kAXWindowsAttribute) + offSpaceWindows {
            guard seenElements.insert(element).inserted else { continue }
            AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
            guard let frame = element.frame else { continue } // closed since the scan
            let title = element.string(kAXTitleAttribute) ?? ""
            let subrole = element.string(kAXSubroleAttribute)
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
    /// Don't rescan an app more than this often when CG keeps reporting a window AX can't see
    /// (e.g. a window type we filter out).
    private var lastScan: [pid_t: Date] = [:]
    private let minimumInterval: TimeInterval = 5
    private let queue = DispatchQueue(label: "OffSpaceWindowCache", qos: .utility)

    func windows(of pid: pid_t) -> [AXUIElement] {
        lock.withLock { byPid[pid] ?? [] }
    }

    func forget(_ pid: pid_t) {
        lock.withLock {
            byPid[pid] = nil
            lastScan[pid] = nil
        }
    }

    func scan(_ pids: [pid_t], force: Bool = false) {
        let now = Date()
        let todo: [pid_t] = lock.withLock {
            let due = pids.filter { pid in
                !scanning.contains(pid) && (force || now.timeIntervalSince(lastScan[pid] ?? .distantPast) > minimumInterval)
            }
            scanning.formUnion(due)
            return due
        }
        guard !todo.isEmpty else { return }
        queue.async { [self] in
            let start = Date()
            var results = [[AXUIElement]](repeating: [], count: todo.count)
            let resultsLock = NSLock()
            DispatchQueue.concurrentPerform(iterations: todo.count) { index in
                let windows = PrivateAX.allWindows(of: todo[index])
                resultsLock.withLock { results[index] = windows }
            }
            lock.withLock {
                for (pid, windows) in zip(todo, results) {
                    byPid[pid] = windows
                    lastScan[pid] = Date()
                    scanning.remove(pid)
                }
            }
            Log.perf.debug("Scanned \(todo.count) apps for windows on other Spaces in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
    }
}
