import Foundation

/// Type-to-filter matching for the overlay.
public enum WindowSearch {
    /// True when every space-separated term of `query` appears in at least one field,
    /// ignoring case and accents. "1056" matches "NINTO-1056"; "code ninto" matches a VS Code
    /// window of a ninto worktree.
    public static func matches(_ query: String, fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        return terms.allSatisfy { term in
            fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
