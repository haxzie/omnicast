import Foundation

/// Persists what the launcher has learned, and logs the decisions it was
/// learned from so the ranking can be scored offline (see `LearningReplay`).
///
/// SQLite is the durable copy; an in-memory `LearningModel` is the read path,
/// because ranking touches it once per keystroke.
final class UsageStore: @unchecked Sendable {
    static let shared = UsageStore()

    /// Picks kept for replay. A few thousand is plenty to tune against and
    /// stays well under a megabyte.
    static let maxLogEntries = 5_000

    /// One logged decision: what was on screen, in order, and which row won.
    struct LoggedPick {
        var query: String
        /// Item ids with the fuzzy score they were ranked on, before learning.
        var shown: [(id: String, base: Double)]
        var pickedID: String
        var createdAt: Date
    }

    private let db: SQLiteDatabase?
    private let lock = NSLock()
    private var model = LearningModel()

    init(directory: URL = SQLiteDatabase.supportDirectory) {
        let database = try? SQLiteDatabase(path: directory.appendingPathComponent("usage.sqlite"))
        try? database?.execute(
            """
            CREATE TABLE IF NOT EXISTS item_usage (
                item_id TEXT PRIMARY KEY,
                launches REAL NOT NULL,
                launches_at INTEGER NOT NULL,
                last_used INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS prefix_usage (
                prefix TEXT NOT NULL,
                item_id TEXT NOT NULL,
                weight REAL NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (prefix, item_id)
            );
            CREATE TABLE IF NOT EXISTS pick_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                query TEXT NOT NULL,
                shown TEXT NOT NULL,
                picked_id TEXT NOT NULL,
                picked_index INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            );
            """)
        db = database
        model = LearningModel(items: loadItems(), prefixes: loadPrefixes())
    }

    // MARK: - Ranking

    func memory(for query: String, at now: Date = Date()) -> LearningModel.Memory {
        lock.withLock { model.memory(for: query, at: now) }
    }

    // MARK: - Learning

    /// Records a pick and logs the decision behind it.
    func record(
        itemID: String, query: String, shown: [(id: String, base: Double)], pickedIndex: Int,
        at now: Date = Date()
    ) {
        let (item, prefixRows) = lock.withLock { model.record(itemID: itemID, query: query, at: now) }

        try? db?.run(
            """
            INSERT INTO item_usage (item_id, launches, launches_at, last_used)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                launches = excluded.launches,
                launches_at = excluded.launches_at,
                last_used = excluded.last_used
            """,
            [
                .text(item.itemID), .double(item.launches.value),
                .int(Self.milliseconds(item.launches.updatedAt)), .int(Self.milliseconds(item.lastUsed)),
            ])

        for row in prefixRows {
            try? db?.run(
                """
                INSERT INTO prefix_usage (prefix, item_id, weight, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(prefix, item_id) DO UPDATE SET
                    weight = excluded.weight,
                    updated_at = excluded.updated_at
                """,
                [
                    .text(row.prefix), .text(row.itemID), .double(row.weight.value),
                    .int(Self.milliseconds(row.weight.updatedAt)),
                ])
        }

        logPick(
            query: LearningModel.key(for: query), shown: shown, pickedID: itemID,
            pickedIndex: pickedIndex, at: now)
    }

    func reset() {
        lock.withLock { model = LearningModel() }
        try? db?.run("DELETE FROM item_usage")
        try? db?.run("DELETE FROM prefix_usage")
        try? db?.run("DELETE FROM pick_log")
    }

    // MARK: - Pick log

    func loggedPicks() -> [LoggedPick] {
        guard let rows = try? db?.query("SELECT * FROM pick_log ORDER BY created_at ASC, id ASC")
        else { return [] }

        return rows.compactMap { row in
            guard let query = row.string("query"), let pickedID = row.string("picked_id"),
                let shown = row.string("shown")
            else { return nil }
            return LoggedPick(
                query: query, shown: Self.decodeShown(shown), pickedID: pickedID,
                createdAt: Date(timeIntervalSince1970: Double(row.int("created_at") ?? 0) / 1000))
        }
    }

    private func logPick(
        query: String, shown: [(id: String, base: Double)], pickedID: String, pickedIndex: Int,
        at now: Date
    ) {
        guard let db, !shown.isEmpty else { return }
        try? db.run(
            """
            INSERT INTO pick_log (query, shown, picked_id, picked_index, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text(query), .text(Self.encodeShown(shown)), .text(pickedID),
                .int(Int64(pickedIndex)), .int(Self.milliseconds(now)),
            ])
        // Keep the log bounded without a sweep: drop anything older than the
        // last `maxLogEntries` rows.
        try? db.run(
            "DELETE FROM pick_log WHERE id <= (SELECT MAX(id) FROM pick_log) - ?",
            [.int(Int64(Self.maxLogEntries))])
    }

    // MARK: - Loading

    private func loadItems() -> [LearningModel.ItemRow] {
        guard let rows = try? db?.query("SELECT * FROM item_usage") else { return [] }
        return rows.compactMap { row in
            guard let id = row.string("item_id"), let launches = row.double("launches") else {
                return nil
            }
            return LearningModel.ItemRow(
                itemID: id,
                launches: LearningModel.Weight(
                    value: launches, updatedAt: Self.date(row.int("launches_at"))),
                lastUsed: Self.date(row.int("last_used")))
        }
    }

    private func loadPrefixes() -> [LearningModel.PrefixRow] {
        guard let rows = try? db?.query("SELECT * FROM prefix_usage") else { return [] }
        return rows.compactMap { row in
            guard let prefix = row.string("prefix"), let id = row.string("item_id"),
                let weight = row.double("weight")
            else { return nil }
            return LearningModel.PrefixRow(
                prefix: prefix, itemID: id,
                weight: LearningModel.Weight(
                    value: weight, updatedAt: Self.date(row.int("updated_at"))))
        }
    }

    // MARK: - Encoding

    private static func encodeShown(_ shown: [(id: String, base: Double)]) -> String {
        // Only the visible head of the list is worth keeping for replay.
        let payload = shown.prefix(10).map { ["i": $0.id, "s": $0.base] as [String: Any] }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    private static func decodeShown(_ json: String) -> [(id: String, base: Double)] {
        guard let data = json.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return payload.compactMap { entry in
            guard let id = entry["i"] as? String else { return nil }
            return (id: id, base: (entry["s"] as? Double) ?? 0)
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func date(_ milliseconds: Int64?) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds ?? 0) / 1000)
    }
}
