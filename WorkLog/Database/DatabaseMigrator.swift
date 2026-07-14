import Foundation

enum DatabaseMigrator {
    static let currentVersion = 3

    static func migrate(_ db: SQLiteDatabase) throws {
        let version = try db.query("PRAGMA user_version").first?["user_version"]?.intValue ?? 0

        guard version <= currentVersion else {
            throw SQLiteDatabaseError.openFailed("数据库版本 \(version) 高于当前 App 支持的版本 \(currentVersion)")
        }

        try db.inTransaction {
            if version < 1 {
                try db.execute("""
                CREATE TABLE IF NOT EXISTS work_months (
                    id TEXT PRIMARY KEY,
                    month TEXT NOT NULL UNIQUE,
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """)
                try db.execute("""
                CREATE TABLE IF NOT EXISTS work_items (
                    id TEXT PRIMARY KEY,
                    month TEXT NOT NULL,
                    title TEXT NOT NULL,
                    note TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT 'todo',
                    module TEXT NOT NULL DEFAULT '',
                    parent_id TEXT,
                    level INTEGER NOT NULL DEFAULT 0,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    raw_text TEXT NOT NULL DEFAULT '',
                    started_at INTEGER,
                    completed_at INTEGER,
                    deleted_at INTEGER,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """)
                try db.execute("CREATE INDEX IF NOT EXISTS idx_work_items_month ON work_items(month)")
                try db.execute("CREATE INDEX IF NOT EXISTS idx_work_items_module ON work_items(module)")
                try db.execute("CREATE INDEX IF NOT EXISTS idx_work_items_status ON work_items(status)")
                try db.execute("CREATE INDEX IF NOT EXISTS idx_work_items_parent_id ON work_items(parent_id)")
                try db.execute("CREATE INDEX IF NOT EXISTS idx_work_items_sort ON work_items(month, sort_order)")
                try db.execute("PRAGMA user_version = 1")
            }

            if version < 2 {
                try addColumnIfNeeded(db, table: "work_items", column: "started_at", definition: "INTEGER")
                try addColumnIfNeeded(db, table: "work_items", column: "deleted_at", definition: "INTEGER")
                try db.execute("CREATE INDEX IF NOT EXISTS idx_work_items_deleted_at ON work_items(deleted_at)")
                try db.execute("PRAGMA user_version = 2")
            }

            if version < 3 {
                // 旧版本状态统一迁移到两状态模型，保留原任务内容。
                try db.execute("UPDATE work_items SET status = 'todo', started_at = NULL, completed_at = NULL WHERE status IN ('doing', 'paused', 'cancelled')")
                try db.execute("DROP TRIGGER IF EXISTS validate_work_item_status_before_insert")
                try db.execute("DROP TRIGGER IF EXISTS validate_work_item_status_before_update")
                try db.execute("""
                CREATE TRIGGER validate_work_item_status_before_insert
                BEFORE INSERT ON work_items
                WHEN NEW.status NOT IN ('todo', 'done')
                BEGIN
                    SELECT RAISE(ABORT, 'invalid work item status');
                END
                """)
                try db.execute("""
                CREATE TRIGGER validate_work_item_status_before_update
                BEFORE UPDATE OF status ON work_items
                WHEN NEW.status NOT IN ('todo', 'done')
                BEGIN
                    SELECT RAISE(ABORT, 'invalid work item status');
                END
                """)
                try db.execute("PRAGMA user_version = 3")
            }
        }
    }

    private static func addColumnIfNeeded(
        _ db: SQLiteDatabase,
        table: String,
        column: String,
        definition: String
    ) throws {
        let columns = try db.query("PRAGMA table_info(\(table))")
        guard !columns.contains(where: { $0["name"]?.stringValue == column }) else { return }
        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
