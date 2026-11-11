import Foundation

struct VisitedURL: Identifiable, Hashable {
    var id: String { host }
    var host: String
    /// The full address last opened for this host.
    var url: String
    var visits: Int
    var lastVisited: Date
    var faviconPath: String?
}

/// Remembers the addresses you open from the launcher, so typing `git` can
/// offer github.com before you finish the word.
final class URLHistoryStore: @unchecked Sendable {
    static let shared = URLHistoryStore()

    private let db: SQLiteDatabase?
    let faviconDirectory: URL

    init(directory: URL = SQLiteDatabase.supportDirectory) {
        faviconDirectory = directory.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: faviconDirectory, withIntermediateDirectories: true)

        let database = try? SQLiteDatabase(path: directory.appendingPathComponent("urls.sqlite"))
        try? database?.execute(
            """
            CREATE TABLE IF NOT EXISTS visited_urls (
                host TEXT PRIMARY KEY,
                url TEXT NOT NULL,
                visits INTEGER NOT NULL DEFAULT 1,
                last_visited INTEGER NOT NULL,
                favicon_path TEXT
            );
            CREATE INDEX IF NOT EXISTS visited_urls_visits ON visited_urls(visits DESC);
            """)
        db = database
    }

    /// One row per host: visiting github.com/one then github.com/two keeps a
    /// single suggestion rather than cluttering the list with paths.
    func record(_ url: URL, at now: Date = Date()) {
        let host = URLDetector.host(of: url)
        guard !host.isEmpty else { return }
        try? db?.run(
            """
            INSERT INTO visited_urls (host, url, visits, last_visited)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(host) DO UPDATE SET
                url = excluded.url,
                visits = visited_urls.visits + 1,
                last_visited = excluded.last_visited
            """,
            [
                .text(host), .text(url.absoluteString),
                .int(Int64(now.timeIntervalSince1970 * 1000)),
            ])
    }

    func setFavicon(path: String, host: String) {
        try? db?.run(
            "UPDATE visited_urls SET favicon_path = ? WHERE host = ?", [.text(path), .text(host)])
    }

    func all(limit: Int = 200) -> [VisitedURL] {
        rows("SELECT * FROM visited_urls ORDER BY visits DESC, last_visited DESC LIMIT ?",
             [.int(Int64(limit))])
    }

    func entry(host: String) -> VisitedURL? {
        rows("SELECT * FROM visited_urls WHERE host = ? LIMIT 1", [.text(host)]).first
    }

    func forget(host: String) {
        try? db?.run("DELETE FROM visited_urls WHERE host = ?", [.text(host)])
    }

    func forgetAll() {
        try? db?.run("DELETE FROM visited_urls")
        try? FileManager.default.removeItem(at: faviconDirectory)
        try? FileManager.default.createDirectory(
            at: faviconDirectory, withIntermediateDirectories: true)
    }

    private func rows(_ sql: String, _ params: [SQLiteDatabase.Value]) -> [VisitedURL] {
        guard let rows = try? db?.query(sql, params) else { return [] }
        return rows.compactMap { row in
            guard let host = row.string("host"), let url = row.string("url") else { return nil }
            return VisitedURL(
                host: host, url: url, visits: Int(row.int("visits") ?? 1),
                lastVisited: Date(timeIntervalSince1970: Double(row.int("last_visited") ?? 0) / 1000),
                faviconPath: row.string("favicon_path"))
        }
    }
}
