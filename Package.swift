// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WindowSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (filtering, MRU, state machine, layout) so it can be unit tested.
        .target(name: "SwitcherCore", path: "Sources/SwitcherCore"),
        // The app talks to AX / CGEventTap / ScreenCaptureKit, whose CF types aren't Sendable,
        // so it builds in Swift 5 language mode. Everything UI-facing is still @MainActor.
        .executableTarget(
            name: "WindowSwitcher",
            dependencies: ["SwitcherCore"],
            path: "Sources/WindowSwitcher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WindowSwitcherTests",
            dependencies: ["SwitcherCore"],
            path: "Tests/WindowSwitcherTests"
        ),
    ]
)
