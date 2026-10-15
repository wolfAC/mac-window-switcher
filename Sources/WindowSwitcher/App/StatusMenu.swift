import AppKit

@MainActor
protocol StatusMenuDelegate: AnyObject {
    var isPaused: Bool { get }
    var permissionsMissing: Bool { get }
    func showPermissions()
    func showSettings()
    func togglePause()
    func dumpWindows()
}

/// Menu bar item: Settings…, Pause, About, Quit, plus a warning when permissions are missing.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var delegate: StatusMenuDelegate?

    init(delegate: StatusMenuDelegate) {
        self.delegate = delegate
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        let missing = delegate?.permissionsMissing ?? false
        let paused = delegate?.isPaused ?? false
        let symbol = missing ? "exclamationmark.triangle" : paused ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle"
        let description = missing ? String(localized: "Window Switcher: permissions needed") : String(localized: "Window Switcher")
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        item.button?.toolTip = description
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let delegate else { return }

        if delegate.permissionsMissing {
            menu.addItem(entry(String(localized: "Permissions Needed…"), #selector(showPermissions)))
            menu.addItem(.separator())
        }
        menu.addItem(entry(String(localized: "Settings…"), #selector(showSettings), key: ","))
        let pause = entry(String(localized: "Pause Window Switcher"), #selector(togglePause))
        pause.state = delegate.isPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())

        let debug = NSMenuItem(title: String(localized: "Debug"), action: nil, keyEquivalent: "")
        debug.submenu = NSMenu()
        debug.submenu?.addItem(entry(String(localized: "Dump Windows to Log"), #selector(dumpWindows)))
        menu.addItem(debug)

        menu.addItem(entry(String(localized: "About Window Switcher"), #selector(about)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit Window Switcher"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showPermissions() { delegate?.showPermissions() }
    @objc private func showSettings() { delegate?.showSettings() }
    @objc private func togglePause() { delegate?.togglePause() }
    @objc private func dumpWindows() { delegate?.dumpWindows() }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
