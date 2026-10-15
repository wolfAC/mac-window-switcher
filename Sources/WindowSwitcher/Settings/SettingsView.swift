import AppKit
import SwiftUI
import SwitcherCore

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(preferences: preferences)))
            window.title = String(localized: "Window Switcher Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        if let window, !window.isVisible {
            // Size to the SwiftUI content before centring, or the window lands at the top of the screen.
            window.setContentSize(window.contentViewController?.view.fittingSize ?? window.frame.size)
            window.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Hold", selection: $preferences.primaryModifier) {
                    ForEach(TriggerModifier.allCases) { Text($0.title).tag($0) }
                }
                Picker("Also", selection: $preferences.secondaryModifier) {
                    Text("None").tag(TriggerModifier?.none)
                    ForEach(TriggerModifier.allCases.filter { $0 != preferences.primaryModifier }) {
                        Text($0.title).tag(TriggerModifier?.some($0))
                    }
                }
                Text("Then press Tab. Add Shift to go backwards.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Windows") {
                Picker("Show windows from", selection: $preferences.scope) {
                    Text("All Spaces and screens").tag(WindowScope.all)
                    Text("Current Space only").tag(WindowScope.currentSpace)
                    Text("Current screen only").tag(WindowScope.currentScreen)
                }
                Toggle("Include minimised windows", isOn: $preferences.includeMinimized)
                Toggle("Include windows of hidden apps", isOn: $preferences.includeHidden)
            }

            Section("Appearance") {
                Picker("Preview size", selection: $preferences.thumbnailSize) {
                    Text("Small").tag(ThumbnailSize.small)
                    Text("Medium").tag(ThumbnailSize.medium)
                    Text("Large").tag(ThumbnailSize.large)
                }
                Toggle("Show window titles", isOn: $preferences.showTitles)
                Picker("Theme", selection: $preferences.appearance) {
                    Text("Match system").tag(AppearanceMode.auto)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
            }

            Section("Behaviour") {
                LabeledContent("Show overlay after") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(preferences.holdDelayMs) },
                            set: { preferences.holdDelayMs = Int($0) }
                        ), in: 0...500, step: 10)
                        Text("\(preferences.holdDelayMs) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                }
                Picker("Show overlay on", selection: $preferences.overlayScreen) {
                    Text("Screen with the active window").tag(OverlayScreen.activeWindow)
                    Text("Screen with the mouse").tag(OverlayScreen.mouse)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
