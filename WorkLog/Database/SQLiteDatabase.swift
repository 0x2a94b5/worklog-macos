import Foundation
import SQLite3

enum SQLiteDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "无法打开数据库：\(message)"
        case .prepareFailed(let message): return "数据库语句准备失败：\(message)"
        case .stepFailed(let message): return "数据库操作失败：\(message)"
        case .bindFailed(let message): return "数据库参数绑定失败：\(message)"
        case .backupFailed(let message): return "数据库备份失败：\(message)"
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String, readOnly: Bool = false) throws {
        let openResult: Int32
        if readOnly {
            let readOnlyURI = URL(fileURLWithPath: path).absoluteString + "?immutable=1"
            openResult = sqlite3_open_v2(
                readOnlyURI,
                &db,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI,
                nil
            )
        } else {
            openResult = sqlite3_open(path, &db)
        }

        if openResult != SQLITE_OK {
            let message = SQLiteDatabase.message(from: db)
            sqlite3_close(db)
            db = nil
            throw SQLiteDatabaseError.openFailed(message)
        }

        if !readOnly {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA busy_timeout = 5000")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String, parameters: [SQLiteValue] = []) throws {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteDatabaseError.prepareFailed(lastMessage)
        }
        defer { sqlite3_finalize(statement) }

        try bind(parameters, to: statement)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            if result == SQLITE_ROW {
                continue
            }
            throw SQLiteDatabaseError.stepFailed(lastMessage)
        }
    }

    func query(_ sql: String, parameters: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteDatabaseError.prepareFailed(lastMessage)
        }
        defer { sqlite3_finalize(statement) }

        try bind(parameters, to: statement)

        var rows: [[String: SQLiteValue]] = []

        while true {
            let result = sqlite3_step(statement)

            if result == SQLITE_ROW {
                rows.append(readRow(from: statement))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw SQLiteDatabaseError.stepFailed(lastMessage)
            }
        }

        return rows
    }

    func performMaintenance() throws {
        try execute("PRAGMA optimize")
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    func quickCheck() throws -> Bool {
        try query("PRAGMA quick_check").first?["quick_check"]?.stringValue == "ok"
    }

    func inTransaction(_ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func backup(to destinationURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        var destination: OpaquePointer?
        guard sqlite3_open(destinationURL.path, &destination) == SQLITE_OK else {
            let message = SQLiteDatabase.message(from: destination)
            sqlite3_close(destination)
            throw SQLiteDatabaseError.backupFailed(message)
        }
        defer { sqlite3_close(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", db, "main") else {
            throw SQLiteDatabaseError.backupFailed(SQLiteDatabase.message(from: destination))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw SQLiteDatabaseError.backupFailed(SQLiteDatabase.message(from: destination))
        }
    }

    private func bind(_ parameters: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            let result: Int32

            switch value {
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, position, integer)
            case .text(let text):
                result = sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
            case .null:
                result = sqlite3_bind_null(statement, position)
            }

            guard result == SQLITE_OK else {
                throw SQLiteDatabaseError.bindFailed(lastMessage)
            }
        }
    }

    private func readRow(from statement: OpaquePointer?) -> [String: SQLiteValue] {
        let columnCount = sqlite3_column_count(statement)
        var row: [String: SQLiteValue] = [:]

        for index in 0..<columnCount {
            guard let cName = sqlite3_column_name(statement, index) else { continue }
            let name = String(cString: cName)
            let type = sqlite3_column_type(statement, index)

            switch type {
            case SQLITE_INTEGER:
                row[name] = .integer(sqlite3_column_int64(statement, index))
            case SQLITE_TEXT:
                if let cText = sqlite3_column_text(statement, index) {
                    row[name] = .text(String(cString: cText))
                } else {
                    row[name] = .text("")
                }
            default:
                row[name] = .null
            }
        }

        return row
    }

    private var lastMessage: String {
        SQLiteDatabase.message(from: db)
    }

    private static func message(from db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "Unknown error" }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
