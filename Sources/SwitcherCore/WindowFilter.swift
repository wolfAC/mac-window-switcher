import CoreGraphics

/// The facts about a window that decide whether it belongs in the switcher.
public struct WindowCandidate: Equatable, Sendable {
    public var subrole: String?
    public var size: CGSize
    /// CG window layer, or nil when the AX window couldn't be matched to a CG window.
    public var layer: Int?
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isOwnProcess: Bool
    public var isOnCurrentSpace: Bool
    /// Index into the screen list of the screen holding most of the window, if any.
    public var screenIndex: Int?

    public init(
        subrole: String?, size: CGSize, layer: Int?, isMinimized: Bool, isAppHidden: Bool,
        isOwnProcess: Bool, isOnCurrentSpace: Bool, screenIndex: Int?
    ) {
        self.subrole = subrole
        self.size = size
        self.layer = layer
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isOwnProcess = isOwnProcess
        self.isOnCurrentSpace = isOnCurrentSpace
        self.screenIndex = screenIndex
    }
}

public enum WindowScope: String, CaseIterable, Sendable {
    case all, currentSpace, currentScreen
}

public struct WindowFilterOptions: Equatable, Sendable {
    public var includeMinimized: Bool
    public var includeHidden: Bool
    public var scope: WindowScope
    /// Screen the overlay is for; only used by `.currentScreen`.
    public var activeScreenIndex: Int?

    public init(includeMinimized: Bool = true, includeHidden: Bool = true, scope: WindowScope = .all, activeScreenIndex: Int? = nil) {
        self.includeMinimized = includeMinimized
        self.includeHidden = includeHidden
        self.scope = scope
        self.activeScreenIndex = activeScreenIndex
    }
}

public enum WindowFilter {
    public static let standardSubrole = "AXStandardWindow"
    /// Anything smaller than this in either dimension is a helper/utility sliver, not a real window.
    public static let minimumSide: CGFloat = 40

    public static func shouldShow(_ window: WindowCandidate, options: WindowFilterOptions) -> Bool {
        if window.isOwnProcess { return false }
        if window.subrole != standardSubrole { return false }
        if window.size.width < minimumSide || window.size.height < minimumSide { return false }
        if let layer = window.layer, layer != 0 { return false }
        if window.isMinimized && !options.includeMinimized { return false }
        if window.isAppHidden && !options.includeHidden { return false }

        // Minimised windows and windows of hidden apps aren't on any Space, so the
        // location scopes only apply to visible windows.
        let isParked = window.isMinimized || window.isAppHidden
        switch options.scope {
        case .all:
            return true
        case .currentSpace:
            return isParked || window.isOnCurrentSpace
        case .currentScreen:
            return isParked || window.screenIndex == options.activeScreenIndex
        }
    }
}
