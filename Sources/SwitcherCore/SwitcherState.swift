/// Inputs to the switcher, from the hotkey tap, timers, the window catalog and the mouse.
public enum SwitcherEvent: Equatable, Sendable {
    /// Tab pressed while the trigger modifier is held. `reverse` when Shift is held too.
    case trigger(reverse: Bool)
    /// The trigger modifier was released.
    case released
    case escape
    case holdElapsed
    /// The window list for this session is ready (or was reloaded after an action).
    /// `previous` is where the previously used window sits in the list: 1 when the list is in
    /// most-recently-used order, elsewhere when windows are grouped by app. A forward session
    /// starts there, so a quick tap still jumps back to the previous window.
    case loaded(count: Int, previous: Int = 1)
    /// Arrow keys: relative move with wrap-around.
    case move(by: Int)
    /// Arrow keys between rows, or mouse hover: absolute selection.
    case select(index: Int)
    /// Mouse click on a cell.
    case click(index: Int)
    /// The search text changed and the list now has `count` matches. Keeps the overlay open
    /// after the modifier is released, and selects the first match.
    case filtered(count: Int)
    /// Return: switch to the selected window.
    case confirm
}

public enum SwitcherEffect: Equatable, Sendable {
    case loadWindows
    case startHoldTimer
    /// Lay out and show (or re-render) the overlay.
    case show
    case updateSelection(Int)
    case hide
    case commit(index: Int)
    case cancel
}

/// idle → active (armed, waiting for the hold delay and the window list) → visible → commit/cancel → idle.
///
/// Tab presses are counted in `steps` until the window list arrives, so pressing Tab
/// three times quickly still lands on the fourth window.
public struct SwitcherState: Equatable, Sendable {
    public private(set) var isActive = false
    public private(set) var isVisible = false
    public private(set) var count: Int?
    private var steps = 0
    private var holdElapsed = false
    private var pendingCommit = false
    private var startedForward = false
    /// Set once the user starts typing: releasing the modifier no longer commits, so they can
    /// let go and type; Return, a click or Escape ends the session.
    public private(set) var isPinned = false

    public init() {}

    public var selection: Int? {
        guard let count, count > 0 else { return nil }
        return ((steps % count) + count) % count
    }

    public mutating func handle(_ event: SwitcherEvent) -> [SwitcherEffect] {
        switch event {
        case .trigger(let reverse):
            let delta = reverse ? -1 : 1
            guard isActive else {
                self = SwitcherState()
                isActive = true
                steps = delta
                startedForward = !reverse
                return [.loadWindows, .startHoldTimer]
            }
            steps += delta
            return isVisible ? selectionEffect() : []

        case .holdElapsed:
            guard isActive, !isVisible else { return [] }
            holdElapsed = true
            return showIfReady()

        case .loaded(let newCount, let previous):
            guard isActive else { return [] }
            let wasLoaded = count != nil
            if wasLoaded, let current = selection {
                // A reload after closing/quitting: stay on the same slot, clamped.
                steps = min(current, max(newCount - 1, 0))
            } else if startedForward, previous > 0, previous < newCount {
                // Tabs pressed so far count on from the previous window, not from slot 1.
                steps += previous - 1
            }
            count = newCount
            if pendingCommit { return finish(commit: true) }
            // While searching, no matches is a valid state: keep the overlay up.
            if newCount == 0 { return isPinned ? [.show] : isVisible ? finish(commit: false) : [] }
            if isVisible { return [.show] + selectionEffect() }
            return showIfReady()

        case .released:
            guard isActive, !isPinned else { return [] }
            if count == nil {
                pendingCommit = true
                return []
            }
            return finish(commit: true)

        case .escape:
            guard isActive else { return [] }
            return finish(commit: false)

        case .filtered(let newCount):
            guard isActive, isVisible else { return [] }
            isPinned = true
            count = newCount
            steps = 0
            return [.show] + selectionEffect()

        case .confirm:
            guard isActive else { return [] }
            if count == nil {
                pendingCommit = true
                return []
            }
            return finish(commit: true)

        case .move(let delta):
            guard isActive, isVisible, let current = selection else { return [] }
            steps = current + delta
            return selectionEffect()

        case .select(let index):
            guard isActive, isVisible, let count, index >= 0, index < count else { return [] }
            if index == selection { return [] }
            steps = index
            return selectionEffect()

        case .click(let index):
            guard isActive, isVisible, let count, index >= 0, index < count else { return [] }
            steps = index
            return finish(commit: true)
        }
    }

    private func selectionEffect() -> [SwitcherEffect] {
        selection.map { [.updateSelection($0)] } ?? []
    }

    private mutating func showIfReady() -> [SwitcherEffect] {
        guard holdElapsed, let count, count > 0 else { return [] }
        isVisible = true
        return [.show] + selectionEffect()
    }

    private mutating func finish(commit: Bool) -> [SwitcherEffect] {
        let target = selection
        let wasVisible = isVisible
        self = SwitcherState()
        var effects: [SwitcherEffect] = wasVisible ? [.hide] : []
        if commit, let target {
            effects.append(.commit(index: target))
        } else {
            effects.append(.cancel)
        }
        return effects
    }
}
