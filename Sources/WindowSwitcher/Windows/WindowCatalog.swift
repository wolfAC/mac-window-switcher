import AppKit
import SwitcherCore

/// Builds the window list from AX (titles, minimised state, control) joined with
/// CGWindowList (window IDs, layer, which windows are on the current Space).
///
/// AX → CG matching uses pid + bounds (+ title as a tie-break) instead of the private
/// `_AXUIElementGetWindow`.
@MainActor
final class WindowCatalog {
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

        let start = Date()
        let all: [RawWindow] = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.collect(apps: apps, screens: screens))
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

    private nonisolated static func collect(apps: [AppRef], screens: [CGRect]) -> [RawWindow] {
        let cgAll = cgWindows(onScreenOnly: false)
        let onScreenIDs = Set(cgWindows(onScreenOnly: true).map(\.id))
        let cgByPid = Dictionary(grouping: cgAll, by: \.pid)

        // AX queries are independent per app and can each wait on a slow app, so run them in parallel.
        var perApp = [[RawWindow]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let windows = windowsOf(apps[index], cgCandidates: cgByPid[apps[index].pid] ?? [], onScreenIDs: onScreenIDs, screens: screens)
            lock.lock()
            perApp[index] = windows
            lock.unlock()
        }

        // Put windows in CG front-to-back order; RecentsTracker refines this into MRU order.
        let zOrder = Dictionary(uniqueKeysWithValues: cgAll.enumerated().map { ($1.id, $0) })
        return perApp.flatMap { $0 }.sorted { a, b in
            (a.window.windowID.flatMap { zOrder[$0] } ?? .max) < (b.window.windowID.flatMap { zOrder[$0] } ?? .max)
        }
    }

    private nonisolated static func windowsOf(_ app: AppRef, cgCandidates: [CGEntry], onScreenIDs: Set<CGWindowID>, screens: [CGRect]) -> [RawWindow] {
        let appElement = AXUIElement.application(app.pid)
        var unmatched = cgCandidates.filter { $0.layer == 0 }
        var result: [RawWindow] = []

        for element in appElement.elements(kAXWindowsAttribute) {
            AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
            guard let frame = element.frame else { continue }
            let title = element.string(kAXTitleAttribute) ?? ""
            let subrole = element.string(kAXSubroleAttribute)
            let minimized = element.bool(kAXMinimizedAttribute) ?? false

            let matches = unmatched.enumerated().filter { boundsMatch($0.element.bounds, frame) }
            let match = matches.first { $0.element.title == title } ?? matches.first
            if let match { unmatched.remove(at: match.offset) }

            let info = WindowInfo(
                axElement: element,
                windowID: match?.element.id,
                pid: app.pid,
                appName: app.name,
                appIcon: app.icon,
                title: title,
                frame: frame,
                isMinimized: minimized,
                isAppHidden: app.isHidden,
                isOnCurrentSpace: match.map { onScreenIDs.contains($0.element.id) } ?? false,
                screenIndex: screenIndex(for: frame, screens: screens)
            )
            result.append(RawWindow(window: info, subrole: subrole, layer: match?.element.layer))
        }
        return result
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
