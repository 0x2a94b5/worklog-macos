import Foundation

enum CoreTestError: Error {
    case failed(String)
}

@main
struct CoreRegressionTests {
    static func main() throws {
        try testMarkdownRoundTrip()
        try testMigrationTransactionsAndBackup()
        print("Core regression tests passed")
    }

    private static func testMarkdownRoundTrip() throws {
        let parsed = MarkdownParser.parse("""
        2026-07
        ---
        [x]完成项
        4. 主任务
           - 子任务
        """)

        try expect(parsed.month == "2026-07", "应识别合法月份")
        try expect(parsed.items.count == 3, "应解析主任务和子任务")
        try expect(parsed.items[0].status == .done, "[x] 应映射为已完成")
        try expect(parsed.items[2].parentId == parsed.items[1].id, "子任务应关联主任务")
        try expect(parsed.items.allSatisfy { $0.module == ModuleDefaults.uncategorized }, "Markdown 缺少分类时应使用未分类")
        let keywordItem = MarkdownParser.parse("[ ]缴费与支付功能").items.first
        try expect(keywordItem?.module == ModuleDefaults.uncategorized, "标题关键词不应触发隐藏分类推断")

        var itemWithPrivateData = parsed.items[0]
        itemWithPrivateData.module = "内部分类"
        itemWithPrivateData.note = "内部备注"
        let markdown = MarkdownParser.export(month: parsed.month, items: [itemWithPrivateData])
        try expect(markdown.contains("[x]完成项"), "导出应保留标准 Markdown 状态")
        try expect(!markdown.contains("内部分类") && !markdown.contains("内部备注"), "导出不应包含内部字段")
        try expect(DateUtils.isValidMonth("2026-07") && !DateUtils.isValidMonth("2026-13"), "月份校验应限制到 01...12")
    }

    private static func testMigrationTransactionsAndBackup() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkLogCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceURL = folder.appendingPathComponent("source.sqlite")
        let db = try SQLiteDatabase(path: sourceURL.path)
        try db.execute("""
        CREATE TABLE work_items (
            id TEXT PRIMARY KEY, month TEXT NOT NULL, title TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'todo',
            module TEXT NOT NULL DEFAULT '', parent_id TEXT, level INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0, raw_text TEXT NOT NULL DEFAULT '',
            completed_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )
        """)
        try db.execute("""
        INSERT INTO work_items
            (id, month, title, status, created_at, updated_at)
        VALUES ('legacy', '2026-07', '旧进行中任务', 'doing', 1, 1)
        """)

        try DatabaseMigrator.migrate(db)
        let migrated = try db.query("SELECT status FROM work_items WHERE id = 'legacy'")
        try expect(migrated.first?["status"]?.stringValue == "todo", "旧 doing 状态应迁移为 todo")
        let version = try db.query("PRAGMA user_version").first?["user_version"]?.intValue
        try expect(version == 3, "数据库版本应迁移到 3")

        do {
            try db.execute("UPDATE work_items SET status = 'doing' WHERE id = 'legacy'")
            throw CoreTestError.failed("两状态触发器应拒绝 doing")
        } catch let error as SQLiteDatabaseError {
            guard case .stepFailed = error else { throw error }
        }

        do {
            try db.inTransaction {
                try db.execute("UPDATE work_items SET title = '不应提交' WHERE id = 'legacy'")
                throw CoreTestError.failed("主动回滚")
            }
        } catch CoreTestError.failed(let reason) where reason == "主动回滚" {}
        let rolledBack = try db.query("SELECT title FROM work_items WHERE id = 'legacy'")
        try expect(rolledBack.first?["title"]?.stringValue == "旧进行中任务", "事务失败后应回滚")

        let backupURL = folder.appendingPathComponent("backup.sqlite")
        try db.backup(to: backupURL)
        let backupDB = try SQLiteDatabase(path: backupURL.path)
        let quickCheck = try backupDB.query("PRAGMA quick_check").first?["quick_check"]?.stringValue
        try expect(quickCheck == "ok", "SQLite 备份应完整可读")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CoreTestError.failed(message) }
    }
}
