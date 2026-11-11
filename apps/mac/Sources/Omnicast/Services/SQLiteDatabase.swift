import Foundation
import SQLite3

/// Minimal, dependency-free SQLite wrapper. Omnicast stores clipboard and
/// dictation history locally, so the storage layer has to be cheap to open and
/// safe to touch from a background queue.
final class SQLiteDatabase {
    enum Value {
        case text(String)
        case int(Int64)
        case double(Double)
        case blob(Data)
        case null
    }

    struct Row {
        private let storage: [String: Value]

        init(_ storage: [String: Value]) { self.storage = storage }

        func string(_ column: String) -> String? {
            if case .text(let v) = storage[column] ?? .null { return v }
            return nil
        }

        func int(_ column: String) -> Int64? {
            if case .int(let v) = storage[column] ?? .null { return v }
            return nil
        }

        func double(_ column: String) -> Double? {
            switch storage[column] ?? .null {
            case .double(let v): return v
            case .int(let v): return Double(v)
            default: return nil
            }
        }

        func data(_ column: String) -> Data? {
            if case .blob(let v) = storage[column] ?? .null { return v }
            return nil
        }
    }

    struct Error: Swift.Error, CustomStringConvertible {
        let description: String
    }

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "app.omnicast.sqlite")

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw Error(description: "Unable to open database at \(path.path)")
        }
        self.handle = handle
        // WAL keeps the launcher's reads from blocking the clipboard writer.
        try execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func execute(_ sql: String) throws {
        try queue.sync {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
                defer { sqlite3_free(error) }
                throw Error(description: error.map { String(cString: $0) } ?? "sqlite3_exec failed")
            }
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [Value] = []) throws -> Int64 {
        try queue.sync {
            let statement = try prepare(sql, params)
            defer { sqlite3_finalize(statement) }
            let status = sqlite3_step(statement)
            guard status == SQLITE_DONE || status == SQLITE_ROW else {
                throw Error(description: lastErrorMessage())
            }
            return sqlite3_last_insert_rowid(handle)
        }
    }

    func query(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        try queue.sync {
            let statement = try prepare(sql, params)
            defer { sqlite3_finalize(statement) }

            var rows: [Row] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                var values: [String: Value] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    values[name] = value(of: statement, at: index)
                }
                rows.append(Row(values))
            }
            return rows
        }
    }

    // MARK: - Internals

    private func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error(description: lastErrorMessage())
        }
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            switch param {
            case .text(let value):
                sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .int(let value):
                sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                sqlite3_bind_double(statement, index, value)
            case .blob(let value):
                _ = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                }
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func value(of statement: OpaquePointer?, at index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: return .double(sqlite3_column_double(statement, index))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else { return .null }
            return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))))
        case SQLITE_NULL: return .null
        default:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: text))
        }
    }

    private func lastErrorMessage() -> String {
        guard let message = sqlite3_errmsg(handle) else { return "unknown sqlite error" }
        return String(cString: message)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension SQLiteDatabase {
    /// `~/Library/Application Support/Omnicast`
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Omnicast", isDirectory: true)
    }
}
