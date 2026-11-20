import Foundation

/// How a window is named in the switcher.
public enum NamingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The window's own title.
    case title
    /// Just the app's name, e.g. "Discord".
    case appName
    /// The last "—"-separated part of the title: the folder or worktree in VS Code and
    /// Cursor ("main.swift — my-repo" → "my-repo"), without the current file.
    case projectFolder
    /// The profile Chrome-style browsers append to the title
    /// ("Page - Google Chrome - Work" → "Work"); the app name when there's only one profile.
    case browserProfile
    /// Terminal.app's tab title without the user name, running processes and window size
    /// ("wolf — ✳ My session — caffeinate ◂ claude — 80×24" → "My session").
    case terminal
    /// The first capture group (or the whole match) of a regular expression.
    case custom

    public var id: String { rawValue }
}

/// A naming rule for one app, matched by bundle identifier.
public struct NamingRule: Codable, Identifiable, Equatable, Sendable {
    public var bundleID: String
    /// Shown in Settings; the app may not be running.
    public var appName: String
    public var style: NamingStyle
    /// Regular expression for `.custom`.
    public var pattern: String

    public var id: String { bundleID }

    public init(bundleID: String, appName: String, style: NamingStyle, pattern: String = "") {
        self.bundleID = bundleID
        self.appName = appName
        self.style = style
        self.pattern = pattern
    }

    public static let defaults: [NamingRule] = [
        NamingRule(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", style: .projectFolder),
        NamingRule(bundleID: "com.google.Chrome", appName: "Google Chrome", style: .browserProfile),
        NamingRule(bundleID: "com.hnc.Discord", appName: "Discord", style: .appName),
        NamingRule(bundleID: "com.apple.Terminal", appName: "Terminal", style: .terminal),
    ]
}

public enum WindowNaming {
    /// The name to show. Falls back to the full title, then the app name, whenever a rule
    /// finds nothing, so a window is never left blank.
    public static func name(title: String, appName: String, style: NamingStyle, pattern: String = "", userName: String = NSUserName()) -> String {
        let fallback = title.isEmpty ? appName : title
        let result: String? = switch style {
        case .title: fallback
        case .appName: appName
        case .projectFolder: projectFolder(in: title, appName: appName)
        case .browserProfile: browserProfile(in: title, appName: appName)
        case .terminal: terminalTitle(in: title, userName: userName)
        case .custom: match(pattern, in: title)
        }
        let trimmed = result?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func projectFolder(in title: String, appName: String) -> String? {
        let parts = title.components(separatedBy: " — ").map { $0.trimmingCharacters(in: .whitespaces) }
        // Settings can add the app's own name as the last part ("file — folder — Visual Studio Code").
        let meaningful = parts.filter { !$0.isEmpty && $0 != appName && $0 != "Visual Studio Code" }
        guard meaningful.count > 1 || parts.count > 1 else { return nil }
        return meaningful.last
    }

    static func browserProfile(in title: String, appName: String) -> String? {
        for separator in [" - ", " — ", " – "] {
            let marker = separator + appName + separator
            if let range = title.range(of: marker, options: .backwards) {
                return String(title[range.upperBound...])
            }
        }
        // Only one profile: Chrome adds no suffix, so there's no profile to tell apart.
        return appName
    }

    static func terminalTitle(in title: String, userName: String) -> String? {
        var parts = title.components(separatedBy: " — ").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == userName { parts.removeFirst() }
        parts.removeAll { part in
            part.isEmpty
                || part.range(of: #"^\d+×\d+$"#, options: .regularExpression) != nil // window size
                || part.contains(" ◂ ") // process chain, e.g. "caffeinate ◂ claude"
        }
        guard var name = parts.first else { return nil }
        // Status icons programs put in front of the title (Claude Code's ✳ / spinner, etc.).
        if let range = name.range(of: #"^[^\p{L}\p{N}\-~/.]+\s+"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    static func match(_ pattern: String, in title: String) -> String? {
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let result = regex.firstMatch(in: title, range: range) else { return nil }
        let group = result.numberOfRanges > 1 && result.range(at: 1).location != NSNotFound ? result.range(at: 1) : result.range
        return Range(group, in: title).map { String(title[$0]) }
    }
}
