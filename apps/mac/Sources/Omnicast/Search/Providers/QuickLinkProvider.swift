import AppKit
import Foundation

/// Folders worth reaching without opening Finder first — the Trash, your
/// Downloads, the Applications folder.
///
/// Each one is a real path, checked before it is offered, so a link never
/// points at somewhere that does not exist on this Mac.
final class QuickLinkProvider: SearchProvider, @unchecked Sendable {
    let identifier = "quicklinks"

    private struct Link {
        let name: String
        let path: String
        let keywords: String
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private static let links: [Link] = [
        Link(name: "Trash", path: "\(home)/.Trash", keywords: "trash bin deleted rubbish garbage"),
        Link(name: "Applications", path: "/Applications", keywords: "applications apps programs"),
        Link(name: "Downloads", path: "\(home)/Downloads", keywords: "downloads downloaded"),
        Link(name: "Documents", path: "\(home)/Documents", keywords: "documents docs files"),
        Link(name: "Desktop", path: "\(home)/Desktop", keywords: "desktop"),
        Link(name: "Home", path: home, keywords: "home user folder house"),
        Link(name: "Pictures", path: "\(home)/Pictures", keywords: "pictures photos images"),
        Link(name: "Movies", path: "\(home)/Movies", keywords: "movies videos films"),
        Link(name: "Music", path: "\(home)/Music", keywords: "music audio songs"),
        Link(
            name: "Utilities", path: "/System/Applications/Utilities",
            keywords: "utilities tools system"),
        Link(
            name: "iCloud Drive",
            path: "\(home)/Library/Mobile Documents/com~apple~CloudDocs",
            keywords: "icloud drive cloud"),
    ]

    /// Resolved once: these do not come and go while the app is running.
    private static let available: [Link] = links.filter {
        FileManager.default.fileExists(atPath: $0.path)
    }

    func items(for query: String) async -> [SearchItem] {
        Self.available.compactMap { link -> SearchItem? in
            var match = FuzzyMatcher.Match(score: 0, indices: [])
            if !query.isEmpty {
                let byKeyword = FuzzyMatcher.match(needle: query, haystack: link.keywords)
                    .map { FuzzyMatcher.Match(score: $0.score * 0.7, indices: []) }
                guard let best = FuzzyMatcher.match(needle: query, haystack: link.name) ?? byKeyword
                else { return nil }
                match = best
            }

            let url = URL(fileURLWithPath: link.path)
            return SearchItem(
                id: "link:\(link.name)",
                title: link.name,
                subtitle: Self.subtitle(for: link),
                kind: .folder,
                icon: Self.icon(for: link),
                action: .openURL(url),
                // Below applications: typing an app's name should never be
                // beaten by a folder that happens to share a few letters.
                weight: 1.05,
                score: match.score,
                titleMatch: match.indices)
        }
    }

    private static func subtitle(for link: Link) -> String {
        link.path.hasPrefix(home) ? "~" + link.path.dropFirst(home.count) : link.path
    }

    /// `.Trash` is hidden, so the workspace hands back a blank document icon
    /// for it. The Trash is the one link that has to be named explicitly —
    /// full or empty, matching the Dock.
    private static func icon(for link: Link) -> SearchItem.Icon {
        guard link.name == "Trash" else { return .file(URL(fileURLWithPath: link.path)) }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: link.path)) ?? []
        return .named(contents.isEmpty ? NSImage.trashEmptyName : NSImage.trashFullName)
    }
}
