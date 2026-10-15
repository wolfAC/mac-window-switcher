/// Most-recently-used order of keys, newest first.
public struct RecentsList<Key: Hashable> {
    public private(set) var keys: [Key] = []
    public let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    public mutating func touch(_ key: Key) {
        keys.removeAll { $0 == key }
        keys.insert(key, at: 0)
        if keys.count > capacity { keys.removeLast(keys.count - capacity) }
    }

    public mutating func remove(_ key: Key) {
        keys.removeAll { $0 == key }
    }

    public mutating func removeAll(where shouldRemove: (Key) -> Bool) {
        keys.removeAll(where: shouldRemove)
    }

    /// Drops keys that aren't in `alive`, e.g. windows that have closed.
    public mutating func retain(_ alive: Set<Key>) {
        keys.removeAll { !alive.contains($0) }
    }

    /// Items with a known key come first, newest first. Unknown items keep their input order after them.
    public func ordered<Item>(_ items: [Item], key: (Item) -> Key) -> [Item] {
        var rank: [Key: Int] = [:]
        for (index, key) in keys.enumerated() { rank[key] = index }
        return items.enumerated()
            .sorted { a, b in
                switch (rank[key(a.element)], rank[key(b.element)]) {
                case let (ra?, rb?): return ra < rb
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.offset < b.offset
                }
            }
            .map(\.element)
    }
}

extension RecentsList: Sendable where Key: Sendable {}
