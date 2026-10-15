import AppKit

struct WindowInfo: Identifiable {
    /// The AX element is the identity: it's stable for a window's lifetime and works for
    /// windows we couldn't match to a CGWindowID.
    var id: AXUIElement { axElement }

    let axElement: AXUIElement
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String
    let appIcon: NSImage?
    let title: String
    /// Global frame, top-left origin.
    let frame: CGRect
    let isMinimized: Bool
    let isAppHidden: Bool
    let isOnCurrentSpace: Bool
    let screenIndex: Int?

    /// Previews need a live, on-screen window.
    var canCapture: Bool {
        windowID != nil && !isMinimized && !isAppHidden && isOnCurrentSpace
    }

    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    var aspectRatio: CGFloat {
        frame.height > 0 ? frame.width / frame.height : 1
    }
}
