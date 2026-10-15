import AppKit
import ScreenCaptureKit

/// Window previews via ScreenCaptureKit. Captures run in parallel and are delivered one
/// by one; a missing preview never blocks the overlay (cells show the app icon until then).
@MainActor
final class ThumbnailService {
    private var cache: [CGWindowID: CGImage] = [:]
    private var task: Task<Void, Never>?
    private var generation = 0

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func cached(_ id: CGWindowID?) -> CGImage? {
        id.flatMap { cache[$0] }
    }

    /// Discards previews of windows that no longer exist.
    func prune(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }

    /// - Parameter pointSize: the cell's thumbnail area in points. Previews are captured at about 2× that.
    func refresh(
        _ windows: [WindowInfo],
        pointSize: @escaping (WindowInfo) -> CGSize,
        onImage: @escaping (CGWindowID, CGImage) -> Void,
        onFinished: @escaping (Int) -> Void
    ) {
        cancel()
        guard hasPermission else { return }
        let targets = windows.filter(\.canCapture)
        guard !targets.isEmpty else { return }
        let sizes = targets.map(pointSize)
        let current = generation

        task = Task { [weak self] in
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            } catch {
                Log.thumbnails.error("SCShareableContent failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })

            var delivered = 0
            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for (window, size) in zip(targets, sizes) {
                    guard let id = window.windowID, let scWindow = byID[id] else { continue }
                    group.addTask {
                        (id, await Self.capture(scWindow, size: size))
                    }
                }
                for await (id, image) in group {
                    guard let image, !Task.isCancelled else { continue }
                    guard let self, self.generation == current else { return }
                    self.cache[id] = image
                    delivered += 1
                    onImage(id, image)
                }
            }
            guard let self, self.generation == current, !Task.isCancelled else { return }
            onFinished(delivered)
        }
    }

    private nonisolated static func capture(_ window: SCWindow, size: CGSize) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let frame = window.frame
        let scale = min(1, min(size.width / max(frame.width, 1), size.height / max(frame.height, 1)))
        // Never upscale beyond the window's own size in points × 2 (Retina).
        config.width = max(Int(frame.width * scale * 2), 1)
        config.height = max(Int(frame.height * scale * 2), 1)
        config.scalesToFit = true
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            Log.thumbnails.debug("Capture of \(window.windowID) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
