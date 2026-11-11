import AppKit
import Foundation

struct ClipboardEntry: Identifiable, Hashable {
    enum Content: String {
        case text, url, color, image, file
    }

    let id: String
    var content: Content
    /// Plain-text payload, or a file path for images.
    var text: String
    var preview: String
    var sourceAppName: String?
    var sourceBundleID: String?
    var copiedAt: Date
    var pinned: Bool
    var imagePath: String?

    var symbolName: String {
        switch content {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

/// Clipboard history on disk, searchable by text and by source app.
final class ClipboardStore: @unchecked Sendable {
    static let shared = ClipboardStore()

    private let db: SQLiteDatabase?
    private let imagesDirectory: URL

    init(directory: URL = SQLiteDatabase.supportDirectory) {
        imagesDirectory = directory.appendingPathComponent("ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        let database = try? SQLiteDatabase(path: directory.appendingPathComponent("clipboard.sqlite"))
        try? database?.execute(
            """
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                text TEXT NOT NULL,
                preview TEXT NOT NULL,
                hash TEXT NOT NULL,
                source_app TEXT,
                source_bundle TEXT,
                image_path TEXT,
                pinned INTEGER NOT NULL DEFAULT 0,
                copied_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS clips_copied_at ON clips(copied_at DESC);
            CREATE INDEX IF NOT EXISTS clips_hash ON clips(hash);
            """)
        db = database
    }

    @discardableResult
    func insert(_ entry: ClipboardEntry) -> Bool {
        guard let db else { return false }
        let hash = Self.hash(entry.text)
        // Re-copying the same thing moves the existing row to the top instead
        // of filling the list with duplicates.
        if let existing = try? db.query("SELECT id FROM clips WHERE hash = ? LIMIT 1", [.text(hash)]),
            let row = existing.first, let id = row.string("id")
        {
            try? db.run(
                "UPDATE clips SET copied_at = ?, source_app = ?, source_bundle = ? WHERE id = ?",
                [
                    .int(Int64(entry.copiedAt.timeIntervalSince1970 * 1000)),
                    entry.sourceAppName.map { .text($0) } ?? .null,
                    entry.sourceBundleID.map { .text($0) } ?? .null,
                    .text(id),
                ])
            return false
        }

        try? db.run(
            """
            INSERT INTO clips (id, content, text, preview, hash, source_app, source_bundle, image_path, pinned, copied_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(entry.id), .text(entry.content.rawValue), .text(entry.text),
                .text(entry.preview), .text(hash),
                entry.sourceAppName.map { .text($0) } ?? .null,
                entry.sourceBundleID.map { .text($0) } ?? .null,
                entry.imagePath.map { .text($0) } ?? .null,
                .int(entry.pinned ? 1 : 0),
                .int(Int64(entry.copiedAt.timeIntervalSince1970 * 1000)),
            ])
        return true
    }

    func recent(limit: Int = 200) -> [ClipboardEntry] {
        rows("SELECT * FROM clips ORDER BY pinned DESC, copied_at DESC LIMIT ?", [.int(Int64(limit))])
    }

    func search(_ query: String, limit: Int = 60) -> [ClipboardEntry] {
        guard !query.isEmpty else { return recent(limit: limit) }
        return rows(
            "SELECT * FROM clips WHERE text LIKE ? OR source_app LIKE ? ORDER BY copied_at DESC LIMIT ?",
            [.text("%\(query)%"), .text("%\(query)%"), .int(Int64(limit))])
    }

    func setPinned(_ pinned: Bool, id: String) {
        try? db?.run("UPDATE clips SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .text(id)])
    }

    func delete(id: String) {
        try? db?.run("DELETE FROM clips WHERE id = ?", [.text(id)])
    }

    func deleteAll() {
        try? db?.run("DELETE FROM clips WHERE pinned = 0")
    }

    /// Drops unpinned clips older than the retention window.
    func prune(retentionDays: Int) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        try? db?.run(
            "DELETE FROM clips WHERE pinned = 0 AND copied_at < ?",
            [.int(Int64(cutoff.timeIntervalSince1970 * 1000))])
    }

    func saveImage(_ data: Data, id: String) -> String? {
        let url = imagesDirectory.appendingPathComponent("\(id).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url.path
    }

    // MARK: - Internals

    private func rows(_ sql: String, _ params: [SQLiteDatabase.Value]) -> [ClipboardEntry] {
        guard let rows = try? db?.query(sql, params) else { return [] }
        return rows.compactMap { row in
            guard let id = row.string("id"), let text = row.string("text") else { return nil }
            return ClipboardEntry(
                id: id,
                content: ClipboardEntry.Content(rawValue: row.string("content") ?? "text") ?? .text,
                text: text,
                preview: row.string("preview") ?? text,
                sourceAppName: row.string("source_app"),
                sourceBundleID: row.string("source_bundle"),
                copiedAt: Date(timeIntervalSince1970: Double(row.int("copied_at") ?? 0) / 1000),
                pinned: (row.int("pinned") ?? 0) == 1,
                imagePath: row.string("image_path"))
        }
    }

    private static func hash(_ text: String) -> String {
        // Content-addressing only needs to catch exact repeats.
        String(text.hashValue)
    }
}
