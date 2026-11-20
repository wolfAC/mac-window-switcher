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

    /// Running apps that don't have a naming rule yet.
    private var addableApps: [(bundleID: String, name: String)] {
        let taken = Set(preferences.namingRules.map(\.bundleID))
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, !taken.contains(id), seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

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
                Toggle("Keep each app's windows together", isOn: $preferences.groupByApp)
                Text("Apps are ordered by their most recent window. A quick tap still goes back to the previous window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach($preferences.namingRules) { $rule in
                    NamingRuleRow(rule: $rule) {
                        preferences.namingRules.removeAll { $0.id == rule.id }
                    }
                }
                HStack {
                    Menu("Add App") {
                        ForEach(addableApps, id: \.bundleID) { app in
                            Button(app.name) {
                                preferences.namingRules.append(NamingRule(bundleID: app.bundleID, appName: app.name, style: .title))
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(addableApps.isEmpty)
                    Spacer()
                    Button("Restore Defaults") { preferences.namingRules = NamingRule.defaults }
                        .disabled(preferences.namingRules == NamingRule.defaults)
                }
            } header: {
                Text("Window names")
            } footer: {
                Text("Project folder shows the part of the title after the last “—”, such as the worktree in VS Code. Browser profile shows the Chrome profile. Terminal tab drops the user name, processes and window size. Apps not listed show the full window title.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Toggle("Check for updates automatically", isOn: $preferences.checkForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One app's naming rule: icon, name, style, and a pattern field for custom rules.
private struct NamingRuleRow: View {
    @Binding var rule: NamingRule
    let onRemove: () -> Void

    private var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private var patternIsValid: Bool {
        rule.pattern.isEmpty || (try? NSRegularExpression(pattern: rule.pattern)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(rule.appName).lineLimit(1)
                Spacer()
                Picker(rule.appName, selection: $rule.style) {
                    Text("Window title").tag(NamingStyle.title)
                    Text("App name").tag(NamingStyle.appName)
                    Text("Project folder").tag(NamingStyle.projectFolder)
                    Text("Browser profile").tag(NamingStyle.browserProfile)
                    Text("Terminal tab").tag(NamingStyle.terminal)
                    Text("Custom pattern").tag(NamingStyle.custom)
                }
                .labelsHidden()
                .fixedSize()
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove")
                .accessibilityLabel("Remove \(rule.appName)")
            }
            if rule.style == .custom {
                TextField("Pattern", text: $rule.pattern, prompt: Text("Regular expression; the first (group) is shown"))
                    .font(.system(.body, design: .monospaced))
                if !patternIsValid {
                    Text("Not a valid regular expression; the full title is shown.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}
