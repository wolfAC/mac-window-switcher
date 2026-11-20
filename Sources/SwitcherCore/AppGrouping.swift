/// Puts each app's windows next to each other.
public enum AppGrouping {
    /// Groups appear in the order of their first item, and items keep their relative order
    /// inside each group. Fed a most-recently-used list, apps come in order of their most
    /// recent window, each followed by its other windows, newest first.
    public static func grouped<Item, Group: Hashable>(_ items: [Item], by group: (Item) -> Group) -> [Item] {
        var order: [Group] = []
        var buckets: [Group: [Item]] = [:]
        for item in items {
            let key = group(item)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.flatMap { buckets[$0] ?? [] }
    }
}
