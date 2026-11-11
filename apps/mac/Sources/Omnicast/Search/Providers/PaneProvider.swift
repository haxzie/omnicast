import Foundation

/// The two browsers reachable from the launcher: clipboard history and
/// dictation recordings. Selecting one descends into it rather than acting.
final class PaneProvider: SearchProvider, @unchecked Sendable {
    let identifier = "panes"

    private struct Pane {
        let mode: SearchEngine.Mode
        let title: String
        let subtitle: String
        let symbol: String
        let keywords: String
    }

    private static let panes = [
        Pane(
            mode: .clipboard, title: "Clipboard History",
            subtitle: "Browse everything you have copied", symbol: "doc.on.clipboard",
            keywords: "clipboard history paste copy clips pasteboard"),
        Pane(
            mode: .dictation, title: "Recordings",
            subtitle: "Browse your dictation transcripts", symbol: "waveform",
            keywords: "recordings dictation transcripts voice speech notes"),
    ]

    func items(for query: String) async -> [SearchItem] {
        Self.panes.compactMap { pane -> SearchItem? in
            var match = FuzzyMatcher.Match(score: 0, indices: [])
            if !query.isEmpty {
                // Keywords match too, but score below a hit on the title.
                let byKeyword = FuzzyMatcher.match(needle: query, haystack: pane.keywords)
                    .map { FuzzyMatcher.Match(score: $0.score * 0.7, indices: []) }
                guard let best = FuzzyMatcher.match(needle: query, haystack: pane.title) ?? byKeyword
                else { return nil }
                match = best
            }
            return SearchItem(
                id: "pane:\(pane.mode.identifier)",
                title: pane.title,
                subtitle: pane.subtitle,
                kind: pane.mode == .clipboard ? .clipboard : .dictation,
                icon: .symbol(pane.symbol),
                action: .openPane(pane.mode),
                // Just above applications: a two-word query for one of these
                // should not lose to an app that happens to fuzzy-match.
                weight: 1.4,
                score: match.score,
                titleMatch: match.indices)
        }
    }
}
