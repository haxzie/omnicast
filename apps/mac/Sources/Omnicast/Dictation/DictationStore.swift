import Foundation

struct DictationEntry: Identifiable, Hashable {
    let id: String
    var text: String
    var durationMs: Int
    var transcribeMs: Int
    var modelID: String
    var appName: String?
    var appBundleID: String?
    var language: String?
    var createdAt: Date

    var wordCount: Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: \.isWhitespace).count
    }

    /// Words per minute of the spoken audio.
    var wordsPerMinute: Int {
        guard durationMs > 0 else { return 0 }
        return Int(Double(wordCount) / (Double(durationMs) / 60_000))
    }
}

final class DictationStore: @unchecked Sendable {
    static let shared = DictationStore()

    private let db: SQLiteDatabase?

    init(directory: URL = SQLiteDatabase.supportDirectory) {
        let database = try? SQLiteDatabase(path: directory.appendingPathComponent("dictation.sqlite"))
        try? database?.execute(
            """
            CREATE TABLE IF NOT EXISTS dictations (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                transcribe_ms INTEGER NOT NULL DEFAULT 0,
                model_id TEXT NOT NULL,
                app_name TEXT,
                app_bundle TEXT,
                language TEXT,
                synced INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS dictations_created_at ON dictations(created_at DESC);
            """)
        db = database
    }

    func insert(_ entry: DictationEntry) {
        try? db?.run(
            """
            INSERT OR REPLACE INTO dictations
                (id, text, duration_ms, transcribe_ms, model_id, app_name, app_bundle, language, synced, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            [
                .text(entry.id), .text(entry.text), .int(Int64(entry.durationMs)),
                .int(Int64(entry.transcribeMs)), .text(entry.modelID),
                entry.appName.map { .text($0) } ?? .null,
                entry.appBundleID.map { .text($0) } ?? .null,
                entry.language.map { .text($0) } ?? .null,
                .int(Int64(entry.createdAt.timeIntervalSince1970 * 1000)),
            ])
    }

    func recent(limit: Int = 200) -> [DictationEntry] {
        rows("SELECT * FROM dictations ORDER BY created_at DESC LIMIT ?", [.int(Int64(limit))])
    }

    func search(_ query: String, limit: Int = 60) -> [DictationEntry] {
        guard !query.isEmpty else { return recent(limit: limit) }
        return rows(
            "SELECT * FROM dictations WHERE text LIKE ? ORDER BY created_at DESC LIMIT ?",
            [.text("%\(query)%"), .int(Int64(limit))])
    }

    func unsynced(limit: Int = 50) -> [DictationEntry] {
        rows("SELECT * FROM dictations WHERE synced = 0 ORDER BY created_at ASC LIMIT ?",
             [.int(Int64(limit))])
    }

    func markSynced(ids: [String]) {
        for id in ids {
            try? db?.run("UPDATE dictations SET synced = 1 WHERE id = ?", [.text(id)])
        }
    }

    func delete(id: String) {
        try? db?.run("DELETE FROM dictations WHERE id = ?", [.text(id)])
    }

    func deleteAll() {
        try? db?.run("DELETE FROM dictations")
    }

    struct Stats {
        var count: Int
        var words: Int
        var seconds: Double
        /// Against a 40 wpm typist.
        var minutesSaved: Double
    }

    func stats() -> Stats {
        guard
            let row = try? db?.query(
                "SELECT COUNT(*) AS c, COALESCE(SUM(duration_ms), 0) AS ms FROM dictations").first,
            let count = row.int("c")
        else { return Stats(count: 0, words: 0, seconds: 0, minutesSaved: 0) }

        let words = recent(limit: 5_000).reduce(0) { $0 + $1.wordCount }
        let seconds = Double(row.int("ms") ?? 0) / 1000
        return Stats(
            count: Int(count), words: words, seconds: seconds,
            minutesSaved: (Double(words) / 40) - (Double(words) / 150))
    }

    private func rows(_ sql: String, _ params: [SQLiteDatabase.Value]) -> [DictationEntry] {
        guard let rows = try? db?.query(sql, params) else { return [] }
        return rows.compactMap { row in
            guard let id = row.string("id"), let text = row.string("text") else { return nil }
            return DictationEntry(
                id: id, text: text,
                durationMs: Int(row.int("duration_ms") ?? 0),
                transcribeMs: Int(row.int("transcribe_ms") ?? 0),
                modelID: row.string("model_id") ?? "unknown",
                appName: row.string("app_name"), appBundleID: row.string("app_bundle"),
                language: row.string("language"),
                createdAt: Date(timeIntervalSince1970: Double(row.int("created_at") ?? 0) / 1000))
        }
    }
}
