import Foundation

/// Past transcripts are searchable from the launcher — handy for re-pasting
/// something you dictated into the wrong window.
final class DictationProvider: SearchProvider, @unchecked Sendable {
    let identifier = "dictation"

    private let store: DictationStore
    private let browsing: Bool

    private static func section(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return "Earlier"
    }

    init(store: DictationStore = .shared, browsing: Bool = false) {
        self.store = store
        self.browsing = browsing
    }

    func items(for query: String) async -> [SearchItem] {
        if query.isEmpty && !browsing { return [] }
        let entries = query.isEmpty ? store.recent(limit: 60) : store.search(query)

        return entries.enumerated().compactMap { index, entry in
            let match = query.isEmpty ? nil : FuzzyMatcher.match(needle: query, haystack: entry.text)
            if !query.isEmpty && match == nil { return nil }
            return SearchItem(
                id: "dictation:\(entry.id)",
                title: entry.text.count > 140 ? String(entry.text.prefix(140)) + "…" : entry.text,
                subtitle:
                    "\(RelativeTime.string(from: entry.createdAt)) · \(entry.wordCount) words",
                kind: .dictation,
                icon: .symbol("waveform"),
                action: .copyText(entry.text),
                weight: 0.9,
                score: (match?.score ?? 0) + (browsing ? Double(1_000 - index) : 0),
                titleMatch: match?.indices ?? [],
                section: Self.section(for: entry.createdAt),
                detail: .dictation(entry))
        }
    }
}
