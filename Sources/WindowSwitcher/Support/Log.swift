import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.wolf.windowswitcher"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let windows = Logger(subsystem: subsystem, category: "windows")
    static let thumbnails = Logger(subsystem: subsystem, category: "thumbnails")
    static let switcher = Logger(subsystem: subsystem, category: "switcher")
    static let perf = Logger(subsystem: subsystem, category: "perf")
}
