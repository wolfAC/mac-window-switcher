import AppKit
import SwiftUI

/// First-run window that walks through both permissions and updates live as they're granted.
@MainActor
final class OnboardingWindow {
    private var window: NSWindow?
    private let permissions: PermissionsService
    private let preferences: Preferences

    init(permissions: PermissionsService, preferences: Preferences) {
        self.permissions = permissions
        self.preferences = preferences
    }

    func show() {
        if window == nil {
            let view = OnboardingView(permissions: permissions) { [weak self] in
                self?.preferences.hasCompletedOnboarding = true
                self?.window?.close()
            }
            let hosting = NSHostingController(rootView: view)
            // Grow and shrink the window as rows appear (Relaunch hint, previews step).
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Welcome to Window Switcher")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        permissions.startPolling(interval: 1)
        if let window, !window.isVisible {
            // Size to the SwiftUI content before centring, or the window lands at the top of the screen.
            window.setContentSize(window.contentViewController?.view.fittingSize ?? window.frame.size)
            window.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsService
    @State private var requestedScreenRecording = false
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Window Switcher needs a few permissions")
                .font(.title2.bold())
            Text("They stay on your Mac. Nothing is recorded or sent anywhere.")
                .foregroundStyle(.secondary)

            PermissionRow(
                granted: permissions.accessibilityGranted,
                title: "Accessibility",
                detail: "To catch ⌘Tab before macOS does, and to focus, close and minimise windows.",
                action: permissions.requestAccessibility
            )
            PermissionRow(
                granted: permissions.screenRecordingGranted,
                title: "Screen Recording",
                detail: "To show a preview of each window. Without it you'll see app icons instead.",
                action: {
                    requestedScreenRecording = true
                    permissions.requestScreenRecording()
                }
            )

            if requestedScreenRecording && !permissions.screenRecordingGranted {
                HStack {
                    Text("Already turned on Screen Recording? macOS applies it after a relaunch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch", action: permissions.relaunch)
                }
            }

            if permissions.needsPreviewApproval {
                PermissionRow(
                    granted: permissions.previewsAllowed,
                    title: "Window Previews",
                    detail: permissions.screenRecordingGranted
                        ? "macOS asks once more to let the app capture windows directly instead of through its window picker. Click Allow when it asks."
                        : "After Screen Recording is on, macOS asks once more to let the app capture windows directly.",
                    buttonTitle: permissions.previewsDeclined ? "Try Again" : "Allow Previews",
                    enabled: permissions.screenRecordingGranted,
                    action: permissions.requestPreviewAccess
                )
                if permissions.previewsDeclined {
                    HStack {
                        Text("Clicked Open System Settings instead? Make sure Window Switcher is on under Screen Recording, then try again.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings", action: permissions.openScreenRecordingSettings)
                    }
                }
            }

            HStack {
                Spacer()
                Button(permissions.allGranted ? "Done" : "Continue Without") { done() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct PermissionRow: View {
    let granted: Bool
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var buttonTitle: LocalizedStringKey = "Open Settings"
    var enabled = true
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
                .accessibilityLabel(granted ? Text("Granted") : Text("Not granted"))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button(buttonTitle, action: action)
                    .disabled(!enabled)
            }
        }
    }
}
