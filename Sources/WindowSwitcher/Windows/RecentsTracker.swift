import AppKit
import SwitcherCore

/// Most-recently-used window order, fed by app activations and by AX focus changes
/// inside each app (so switching between two Safari windows counts too).
@MainActor
final class RecentsTracker {
    private var recents = RecentsList<AXUIElement>()
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.observeWhenReady(app, attempts: 3) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.forget(pid: app.processIdentifier) }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.touchFocusedWindow(of: app.processIdentifier) }
            },
        ]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }
        touchFrontmost()
    }

    func stop() {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens = []
        for pid in Array(observers.keys) { removeObserver(pid: pid) }
    }

    func touch(_ window: AXUIElement) {
        recents.touch(window)
    }

    /// Makes sure the window the user is looking at right now ranks first, even if a
    /// notification was missed.
    func touchFrontmost() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            touchFocusedWindow(of: pid)
        }
    }

    func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        recents.ordered(windows) { $0.axElement }
    }

    /// Drops closed windows. `alive` should be every AX window, not just the visible ones.
    func prune(alive: [WindowInfo]) {
        recents.retain(Set(alive.map(\.axElement)))
    }

    // MARK: - AX observers

    private func touchFocusedWindow(of pid: pid_t) {
        if let window = AXUIElement.application(pid).element(kAXFocusedWindowAttribute) {
            recents.touch(window)
        }
    }

    private func observeWhenReady(_ app: NSRunningApplication, attempts: Int) {
        guard app.activationPolicy == .regular, !app.isTerminated else { return }
        if !observe(app), attempts > 1 {
            // Freshly launched apps often aren't answering AX yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.observeWhenReady(app, attempts: attempts - 1)
            }
        }
    }

    @discardableResult
    private func observe(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return true }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return false }
        let element = AXUIElement.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let added = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification].map {
            AXObserverAddNotification(observer, element, $0 as CFString, refcon)
        }
        guard added.contains(.success) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        return true
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func forget(pid: pid_t) {
        removeObserver(pid: pid)
        recents.removeAll { $0.pid == pid || $0.pid == nil }
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        // For both notifications the element is the newly focused/main window.
        guard element.string(kAXRoleAttribute) == kAXWindowRole else { return }
        recents.touch(element)
    }
}

private func axCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracker = Unmanaged<RecentsTracker>.fromOpaque(refcon).takeUnretainedValue()
    // Observers are added to the main run loop, so this always runs on the main thread.
    MainActor.assumeIsolated {
        tracker.handle(notification: notification as String, element: element)
    }
}
