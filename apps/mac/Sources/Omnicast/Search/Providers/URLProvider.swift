import Foundation

/// Web addresses, from two directions: the one you are typing right now, and
/// the ones you have opened before.
///
/// Both share an id keyed on the host, so opening `github.com` once teaches
/// the ranker that `git` means GitHub — the same prefix memory that learns
/// your applications, with no separate mechanism.
final class URLProvider: SearchProvider, @unchecked Sendable {
    let identifier = "urls"

    private let store: URLHistoryStore

    init(store: URLHistoryStore = .shared) {
        self.store = store
    }

    static func itemID(forHost host: String) -> String { "url:\(host)" }

    func items(for query: String) async -> [SearchItem] {
        var items: [SearchItem] = []
        var seenHosts = Set<String>()

        // What is in the field right now, if it is an address.
        if let url = URLDetector.url(from: query) {
            let host = URLDetector.host(of: url)
            seenHosts.insert(host)
            items.append(
                item(
                    url: url, host: host, subtitle: "Open in your browser",
                    // Typing a full address is unambiguous: nothing should
                    // outrank it.
                    score: 10_000, visits: store.entry(host: host)?.visits ?? 0))
        }

        // Addresses opened before, matched on the host.
        guard !query.isEmpty else { return items }
        for visited in store.all() where !seenHosts.contains(visited.host) {
            guard let match = FuzzyMatcher.match(needle: query, haystack: visited.host),
                let url = URL(string: visited.url)
            else { continue }
            seenHosts.insert(visited.host)
            items.append(
                item(
                    url: url, host: visited.host,
                    subtitle: visited.url, score: match.score, visits: visited.visits,
                    titleMatch: match.indices))
        }
        return items
    }

    private func item(
        url: URL, host: String, subtitle: String, score: Double, visits: Int,
        titleMatch: [Int] = []
    ) -> SearchItem {
        var icon = SearchItem.Icon.symbol("globe")
        if let path = store.entry(host: host)?.faviconPath,
            FileManager.default.fileExists(atPath: path)
        {
            icon = .image(URL(fileURLWithPath: path))
        }

        return SearchItem(
            id: Self.itemID(forHost: host),
            title: host,
            subtitle: subtitle,
            kind: .website,
            icon: icon,
            action: .openURL(url),
            // Somewhere between an application and a folder: a site you visit
            // often should beat an app you never open, but not one you do.
            weight: 1.2,
            // Visits nudge within the websites themselves; the prefix memory
            // does the heavy lifting across kinds.
            score: score + min(Double(visits) * 4, 40),
            titleMatch: titleMatch)
    }
}
