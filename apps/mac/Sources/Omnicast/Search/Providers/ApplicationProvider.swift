import AppKit
import Foundation

/// Indexes every installed app once at launch, then matches in memory. The
/// index is a few hundred entries, so a full scan per keystroke costs
/// microseconds and avoids any Spotlight round trip.
final class ApplicationProvider: SearchProvider, @unchecked Sendable {
    let identifier = "applications"

    private struct Entry {
        let url: URL
        let name: String
        let bundleID: String
        /// "Visual Studio Code" -> "vsc", for acronym matching.
        let acronym: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    /// Apple ships Safari (and a few others) in a sealed cryptex volume;
    /// `/Applications/Safari.app` is only a symlink into it, and the directory
    /// enumerator does not follow symlinks. Without this root the launcher
    /// cannot find Safari at all.
    private static let cryptexApplications =
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications"

    private static let searchRoots: [URL] = {
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: cryptexApplications),
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent("Applications"))
        return roots
    }()

    func prepare() async {
        await reindex()
    }

    func reindex() async {
        let found = await Task.detached(priority: .utility) { Self.scan() }.value
        lock.withLock { entries = found }
    }

    func items(for query: String) async -> [SearchItem] {
        let snapshot = lock.withLock { entries }

        // An empty query is the zero state: hand back every app and let the
        // ranker keep only the ones it can predict from.
        if query.isEmpty {
            return snapshot.map { item(for: $0, match: FuzzyMatcher.Match(score: 0, indices: [])) }
        }

        var results: [SearchItem] = []
        results.reserveCapacity(16)
        for entry in snapshot {
            var best = FuzzyMatcher.match(needle: query, haystack: entry.name)
            // Acronyms ("vsc") are a secondary haystack and score lower than
            // the display name.
            if best == nil, let acronym = FuzzyMatcher.match(needle: query, haystack: entry.acronym) {
                best = FuzzyMatcher.Match(score: acronym.score * 0.8, indices: [])
            }
            // Bundle ids must contain the query outright. Fuzzy-matching them
            // is far too loose — "mail" is a subsequence of "co*m*.*a*pple.*i*Ca*l*".
            if best == nil, entry.bundleID.lowercased().contains(query.lowercased()),
                let bundle = FuzzyMatcher.match(needle: query, haystack: entry.bundleID)
            {
                best = FuzzyMatcher.Match(score: bundle.score * 0.5, indices: [])
            }
            guard let match = best else { continue }

            results.append(item(for: entry, match: match))
        }
        return results
    }

    private func item(for entry: Entry, match: FuzzyMatcher.Match) -> SearchItem {
        SearchItem(
            id: "app:\(entry.bundleID.isEmpty ? entry.url.path : entry.bundleID)",
            title: entry.name,
            subtitle: Self.displayPath(of: entry.url),
            kind: .application,
            icon: .file(entry.url),
            action: .openURL(entry.url),
            weight: 1.35,
            score: match.score,
            titleMatch: match.indices,
            aliases: [entry.bundleID])
    }

    // MARK: - Indexing

    private static func scan() -> [Entry] {
        let manager = FileManager.default
        var seen = Set<String>()
        var found: [Entry] = []

        for root in searchRoots {
            guard
                let enumerator = manager.enumerator(
                    at: root, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for case let url as URL in enumerator {
                // Apps nest at most a couple of levels deep (Utilities, vendor folders).
                if enumerator.level > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                // Dedupe on the real path so an app reachable through a
                // symlink is not listed twice.
                let resolved = url.resolvingSymlinksInPath()
                guard seen.insert(resolved.path).inserted else { continue }
                guard let bundle = Bundle(url: resolved) else { continue }

                let name =
                    (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                found.append(
                    Entry(
                        url: resolved, name: name, bundleID: bundle.bundleIdentifier ?? "",
                        acronym: acronym(of: name)))
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Cryptex paths are an implementation detail — users know Safari as
    /// living in /Applications, which is where the symlink puts it.
    static func displayPath(of url: URL) -> String {
        let parent = url.deletingLastPathComponent().path
        return parent == cryptexApplications ? "/Applications" : parent
    }

    private static func acronym(of name: String) -> String {
        var letters = ""
        var atBoundary = true
        for character in name {
            if character == " " || character == "-" || character == "_" {
                atBoundary = true
            } else {
                if atBoundary || character.isUppercase { letters.append(character) }
                atBoundary = false
            }
        }
        return letters.lowercased()
    }
}
