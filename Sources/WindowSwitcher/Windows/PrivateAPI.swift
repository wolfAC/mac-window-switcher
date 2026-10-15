import AppKit
import ApplicationServices

// Private APIs, used only for windows on other Spaces. The public AX API only lists windows
// on the current Space, and can't bring a window on another Space to the front reliably.
// Everything here has a public fallback, so a macOS update that breaks it degrades to
// "current Space only" rather than crashing.

/// Maps an AX window to its CGWindowID. Stable since macOS 10.x and used by most window managers.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Creates an AX element from a remote token. Lets us reach windows that the app's
/// kAXWindowsAttribute doesn't return because they're on another Space.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

enum PrivateAX {
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    /// Finds every standard window of `pid`, including ones on other Spaces, by trying
    /// AX element IDs one by one. Slow (one IPC round trip per ID), so callers cache it.
    static func allWindows(of pid: pid_t, maxElementID: UInt64 = 1000) -> [AXUIElement] {
        // Token layout: pid (4 bytes), 0 (4 bytes), "coco" magic (4 bytes), element ID (8 bytes).
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        var windows: [AXUIElement] = []
        for elementID in 0..<maxElementID {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
            if element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole {
                windows.append(element)
            }
        }
        return windows
    }
}

/// SkyLight calls that make a specific window key and switch to its Space, the way
/// clicking it would. Loaded at runtime so a missing symbol just disables them.
enum SkyLight {
    private typealias SetFrontProcess = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus

    private struct Functions {
        let setFront: SetFrontProcess
        let postEvent: PostEventRecord
        let processForPID: GetProcessForPID
    }

    private static let functions: Functions? = {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let setFront = dlsym(skyLight, "_SLPSSetFrontProcessWithOptions"),
              let postEvent = dlsym(skyLight, "SLPSPostEventRecordTo"),
              let processForPID = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") // RTLD_DEFAULT
        else {
            Log.windows.notice("SkyLight focus API unavailable; using public activation only")
            return nil
        }
        return Functions(
            setFront: unsafeBitCast(setFront, to: SetFrontProcess.self),
            postEvent: unsafeBitCast(postEvent, to: PostEventRecord.self),
            processForPID: unsafeBitCast(processForPID, to: GetProcessForPID.self)
        )
    }()

    /// Brings `windowID` of `pid` to the front and makes it key, switching Spaces if needed.
    /// Returns false if the private API isn't available or failed.
    @discardableResult
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let functions else { return false }
        // ProcessSerialNumber is two UInt32s.
        var psn = (UInt32(0), UInt32(0))
        return withUnsafeMutableBytes(of: &psn) { psnBytes in
            let psnPointer = psnBytes.baseAddress!
            guard functions.processForPID(pid, psnPointer) == noErr else { return false }
            let userGenerated: UInt32 = 0x200
            guard functions.setFront(psnPointer, windowID, userGenerated) == .success else { return false }

            // Synthetic "make key window" event: a 0xf8-byte record, sent as down (1) then up (2).
            var record = [UInt8](repeating: 0, count: 0xf8)
            record[0x04] = 0xf8
            record[0x3a] = 0x10
            withUnsafeBytes(of: windowID) { idBytes in
                for (offset, byte) in idBytes.enumerated() { record[0x3c + offset] = byte }
            }
            for offset in 0x20..<0x30 { record[offset] = 0xff }
            record[0x08] = 0x01
            _ = functions.postEvent(psnPointer, &record)
            record[0x08] = 0x02
            _ = functions.postEvent(psnPointer, &record)
            return true
        }
    }
}
