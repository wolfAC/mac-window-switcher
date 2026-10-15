import AppKit

enum WindowCommand {
    case close, minimize, quit, hide
}

/// Focus / close / minimise / hide / quit through AX and NSRunningApplication.
/// AX calls wait on the target app, so they run off the main thread.
enum WindowActions {
    private static let queue = DispatchQueue(label: "WindowActions", qos: .userInteractive)

    static func focus(_ window: WindowInfo) {
        let element = window.axElement
        let pid = window.pid
        let wasHidden = window.isAppHidden
        let wasMinimized = window.isMinimized
        queue.async {
            let app = NSRunningApplication(processIdentifier: pid)
            if wasHidden { app?.unhide() }
            if wasMinimized { element.set(kAXMinimizedAttribute, kCFBooleanFalse) }
            // Setting AXFrontmost works from a background (accessory) app, where
            // NSRunningApplication.activate() alone can be refused by cooperative activation.
            AXUIElement.application(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            element.set(kAXMainAttribute, kCFBooleanTrue)
            element.perform(kAXRaiseAction)
            DispatchQueue.main.async {
                app?.activate()
            }
        }
    }

    static func perform(_ command: WindowCommand, on window: WindowInfo) {
        let element = window.axElement
        let pid = window.pid
        queue.async {
            let app = NSRunningApplication(processIdentifier: pid)
            switch command {
            case .close:
                if let button = element.element(kAXCloseButtonAttribute) {
                    button.perform(kAXPressAction)
                }
            case .minimize:
                element.set(kAXMinimizedAttribute, kCFBooleanTrue)
            case .quit:
                app?.terminate()
            case .hide:
                app?.hide()
            }
        }
    }
}
