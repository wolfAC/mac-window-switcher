import AppKit
import ServiceManagement
import SwitcherCore

enum ThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var height: CGFloat {
        switch self {
        case .small: 90
        case .medium: 130
        case .large: 180
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum OverlayScreen: String, CaseIterable, Identifiable {
    case activeWindow, mouse
    var id: String { rawValue }
}

/// Typed UserDefaults. Services read these on every use, so changes apply without a restart.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    @Published var primaryModifier: TriggerModifier { didSet { save(primaryModifier.rawValue, "primaryModifier") } }
    /// Optional second shortcut, e.g. Option+Tab alongside Cmd+Tab.
    @Published var secondaryModifier: TriggerModifier? { didSet { save(secondaryModifier?.rawValue ?? "", "secondaryModifier") } }
    @Published var scope: WindowScope { didSet { save(scope.rawValue, "scope") } }
    @Published var includeMinimized: Bool { didSet { save(includeMinimized, "includeMinimized") } }
    @Published var includeHidden: Bool { didSet { save(includeHidden, "includeHidden") } }
    @Published var thumbnailSize: ThumbnailSize { didSet { save(thumbnailSize.rawValue, "thumbnailSize") } }
    @Published var showTitles: Bool { didSet { save(showTitles, "showTitles") } }
    @Published var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance") } }
    /// How long the modifier must be held before the overlay appears.
    @Published var holdDelayMs: Int { didSet { save(holdDelayMs, "holdDelayMs") } }
    @Published var overlayScreen: OverlayScreen { didSet { save(overlayScreen.rawValue, "overlayScreen") } }
    @Published var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    @Published var checkForUpdates: Bool { didSet { save(checkForUpdates, "checkForUpdates") } }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }
    /// A release the user chose to skip; automatic checks don't offer it again.
    var skippedVersion: String? {
        get { defaults.string(forKey: "skippedVersion") }
        set { defaults.set(newValue, forKey: "skippedVersion") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        primaryModifier = value("primaryModifier", TriggerModifier.command)
        secondaryModifier = defaults.string(forKey: "secondaryModifier").flatMap(TriggerModifier.init(rawValue:))
        scope = value("scope", WindowScope.all)
        includeMinimized = bool("includeMinimized", true)
        includeHidden = bool("includeHidden", true)
        thumbnailSize = value("thumbnailSize", ThumbnailSize.medium)
        showTitles = bool("showTitles", true)
        appearance = value("appearance", AppearanceMode.auto)
        holdDelayMs = defaults.object(forKey: "holdDelayMs") == nil ? 120 : defaults.integer(forKey: "holdDelayMs")
        overlayScreen = value("overlayScreen", OverlayScreen.activeWindow)
        hasCompletedOnboarding = bool("hasCompletedOnboarding", false)
        checkForUpdates = bool("checkForUpdates", true)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    var bindings: [KeyBinding] {
        var result = [KeyBinding(modifier: primaryModifier)]
        if let secondaryModifier, secondaryModifier != primaryModifier {
            result.append(KeyBinding(modifier: secondaryModifier))
        }
        return result
    }

    // MARK: Launch at login (SMAppService, macOS 13+)

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
