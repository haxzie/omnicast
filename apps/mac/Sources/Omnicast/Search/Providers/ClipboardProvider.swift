import Foundation

/// Clipboard history, searchable from the launcher. In clipboard mode the
/// provider returns the whole recent list so the panel doubles as a history
/// browser.
final class ClipboardProvider: SearchProvider, @unchecked Sendable {
    let identifier = "clipboard"

    private let store: ClipboardStore
    /// When true, an empty query lists everything instead of nothing.
    private let browsing: Bool

    init(store: ClipboardStore = .shared, browsing: Bool = false) {
        self.store = store
        self.browsing = browsing
    }

    func items(for query: String) async -> [SearchItem] {
        if query.isEmpty && !browsing { return [] }

        let entries = query.isEmpty ? store.recent(limit: 80) : store.search(query)
        let now = Date()
        return entries.enumerated().map { index, entry in
            let match = query.isEmpty ? nil : FuzzyMatcher.match(needle: query, haystack: entry.preview)
            // Keep the store's recency order when browsing.
            let recencyScore = browsing ? Double(1_000 - index) : 0
            return SearchItem(
                id: "clip:\(entry.id)",
                title: entry.preview.isEmpty ? "(empty)" : entry.preview,
                subtitle: Self.subtitle(for: entry, now: now),
                kind: .clipboard,
                icon: .symbol(entry.pinned ? "pin.fill" : entry.symbolName),
                // Enter copies; the launcher offers paste as the alternate.
                action: .copyText(entry.text),
                weight: browsing ? 1 : 0.95,
                score: (match?.score ?? 0) + recencyScore + (entry.pinned ? 150 : 0),
                titleMatch: match?.indices ?? [],
                section: entry.pinned ? "Pinned" : "Most recent",
                detail: .clipboard(entry))
        }
    }

    private static func subtitle(for entry: ClipboardEntry, now: Date) -> String {
        let source = entry.sourceAppName ?? "Unknown app"
        return "\(source) · \(RelativeTime.string(from: entry.copiedAt, to: now))"
    }
}

enum RelativeTime {
    static func string(from date: Date, to now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        case ..<604_800: return "\(Int(seconds / 86_400))d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}
