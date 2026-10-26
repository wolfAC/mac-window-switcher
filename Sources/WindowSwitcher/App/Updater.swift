import AppKit
import Security
import SwitcherCore

/// Checks GitHub Releases for a newer version and installs it in place: downloads the zip
/// that `release.sh` uploads, checks it is signed by the same certificate as the running
/// app (which also keeps the user's permissions), swaps the bundle and relaunches.
@MainActor
final class Updater {
    nonisolated static let repository = "wolfAC/mac-window-switcher"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let preferences: Preferences
    private var timer: Timer?
    private(set) var isBusy = false
    var onBusyChange: (() -> Void)?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Checks shortly after launch and then about once a day, if enabled in Settings.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard preferences.checkForUpdates else { return }
        if let last = preferences.lastUpdateCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    /// `userInitiated` reports "up to date" and errors, and ignores a skipped version.
    func check(userInitiated: Bool) {
        guard !isBusy else { return }
        setBusy(true)
        Task {
            defer { setBusy(false) }
            do {
                let release = try await Self.fetchLatestRelease()
                preferences.lastUpdateCheck = Date()
                guard let current = Self.currentVersion, release.version > current else {
                    Log.app.notice("Up to date (\(Self.currentVersion?.description ?? "?", privacy: .public), latest \(release.version.description, privacy: .public))")
                    if userInitiated {
                        showAlert(String(localized: "Window Switcher is up to date"),
                                  String(localized: "Version \(Self.currentVersion?.description ?? "?") is the latest."))
                    }
                    return
                }
                if !userInitiated, preferences.skippedVersion == release.version.description { return }
                await offer(release)
            } catch {
                Log.app.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                if userInitiated {
                    showAlert(String(localized: "Couldn't check for updates"), error.localizedDescription)
                }
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        onBusyChange?()
    }

    private func offer(_ release: Release) async {
        let alert = NSAlert()
        alert.messageText = String(localized: "Window Switcher \(release.version.description) is available")
        var info = String(localized: "You have \(Self.currentVersion?.description ?? "?").")
        if let notes = release.notes, !notes.isEmpty {
            info += "\n\n" + (notes.count > 800 ? notes.prefix(800) + "…" : notes)
        }
        alert.informativeText = info
        alert.addButton(withTitle: String(localized: "Install and Relaunch"))
        alert.addButton(withTitle: String(localized: "Later"))
        alert.addButton(withTitle: String(localized: "Skip This Version"))
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try await install(release)
            } catch {
                Log.app.error("Update install failed: \(error.localizedDescription, privacy: .public)")
                let failed = NSAlert()
                failed.messageText = String(localized: "Couldn't install the update")
                failed.informativeText = error.localizedDescription
                failed.addButton(withTitle: String(localized: "Open Download Page"))
                failed.addButton(withTitle: String(localized: "Cancel"))
                NSApp.activate()
                if failed.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
            }
        case .alertThirdButtonReturn:
            preferences.skippedVersion = release.version.description
        default:
            break
        }
    }

    // MARK: Install

    private func install(_ release: Release) async throws {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else { throw UpdateError.notAnAppBundle }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("WindowSwitcherUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let (download, _) = try await URLSession.shared.download(from: release.zip)
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: download, to: zip)
        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

        guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.invalid(String(localized: "The download has no app in it.")) }
        try Self.verify(newApp, expected: release.version)

        _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        Log.app.notice("Installed \(release.version.description, privacy: .public); relaunching")
        try Self.relaunch(target)
        NSApp.terminate(nil)
    }

    /// The new bundle must be the same app, the advertised version, and satisfy the running
    /// app's designated requirement, i.e. be signed with the same certificate.
    private static func verify(_ app: URL, expected: AppVersion) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.invalid(String(localized: "The download is a different app."))
        }
        guard let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version == expected
        else { throw UpdateError.invalid(String(localized: "The download's version doesn't match the release.")) }

        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate
        else { throw UpdateError.invalid(String(localized: "Couldn't read the code signatures.")) }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        guard status == errSecSuccess else {
            throw UpdateError.invalid(String(localized: "The download isn't signed like this copy of Window Switcher (error \(status)). Development builds can't update themselves."))
        }
    }

    /// Waits for this process to exit, then opens the new copy.
    private static func relaunch(_ app: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/xattr -dr com.apple.quarantine \"$1\"; /usr/bin/open \"$1\"",
            "sh", app.path,
        ]
        try process.run()
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.invalid(String(localized: "Couldn't unpack the download.")))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: GitHub

    private static var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    private struct Release {
        let version: AppVersion
        let page: URL
        let zip: URL
        let notes: String?
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        let tagName: String
        let htmlUrl: URL
        let body: String?
        let assets: [Asset]
    }

    /// The newest published release (GitHub's "latest" skips drafts and pre-releases).
    private nonisolated static func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.invalid(String(localized: "GitHub answered with status \((response as? HTTPURLResponse)?.statusCode ?? 0)."))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(release.tagName) else {
            throw UpdateError.invalid(String(localized: "The latest release has an unexpected tag, \(release.tagName)."))
        }
        guard let zip = release.assets.first(where: { $0.name == "WindowSwitcher.zip" })?.browserDownloadUrl else {
            throw UpdateError.invalid(String(localized: "The latest release has no WindowSwitcher.zip."))
        }
        return Release(version: version, page: release.htmlUrl, zip: zip, notes: release.body)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}

private enum UpdateError: LocalizedError {
    case notAnAppBundle
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notAnAppBundle: String(localized: "This copy isn't running from an app bundle, so it can't replace itself.")
        case .invalid(let message): message
        }
    }
}
