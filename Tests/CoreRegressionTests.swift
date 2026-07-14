import Foundation

enum CoreTestError: Error {
    case failed(String)
}

@main
struct CoreRegressionTests {
    static func main() throws {
        try testMarkdownRoundTrip()
        try testMonthlySummaryCompleteness()
        try testMigrationTransactionsAndBackup()
        try testDailyBackupAndDatabaseRecovery()
        try testHierarchicalCompletion()
        print("Core regression tests passed")
    }

    private static func testMonthlySummaryCompleteness() throws {
        var items = (1...9).map { index in
            WorkItem.create(
                month: "2026-07",
                title: "待完成任务 \(index)",
                module: index == 1 ? "云物管" : ""
            )
        }
        let child = WorkItem.create(
            month: "2026-07",
            title: "完整保留的子任务",
            status: .done,
            parentId: items[8].id,
            level: 1
        )
        items.append(child)

        let report = MonthlySummaryFormatter.report(month: "2026-07", items: items)
        try expect(report.contains("待完成任务 9"), "月度复盘不应截断第 9 个主任务")
        try expect(report.contains("完整保留的子任务"), "月度复盘应保留子任务")
        try expect(report.contains("涉及分类：云物管"), "月度复盘应忽略空分类")
        try expect(!report.contains("、云物管"), "分类文本不应产生前导分隔符")
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

    private static func testHierarchicalCompletion() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkLogHierarchyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let db = try SQLiteDatabase(path: folder.appendingPathComponent("hierarchy.sqlite").path)
        try DatabaseMigrator.migrate(db)
        let repository = WorkItemRepository(db: db)

        let parent = WorkItem.create(month: "2026-07", title: "主任务")
        let firstChild = WorkItem.create(month: "2026-07", title: "子任务一", parentId: parent.id, level: 1)
        let secondChild = WorkItem.create(month: "2026-07", title: "子任务二", parentId: parent.id, level: 1)
        try repository.insertMany([parent, firstChild, secondChild])

        try repository.setCompletion(parent, completed: true)
        let completedParent = try repository.fetch(id: parent.id)
        let completedChildren = try repository.fetchChildren(parentId: parent.id)
        try expect(completedParent?.isDone == true, "完成主任务应完成主任务")
        try expect(completedChildren.allSatisfy(\.isDone), "完成主任务应同步完成全部子任务")

        guard let storedFirstChild = try repository.fetch(id: firstChild.id) else {
            throw CoreTestError.failed("应读取到子任务")
        }
        try repository.setCompletion(storedFirstChild, completed: false)
        let reopenedParent = try repository.fetch(id: parent.id)
        try expect(reopenedParent?.isDone == false, "恢复任一子任务应恢复主任务")

        guard let reopenedChild = try repository.fetch(id: firstChild.id) else {
            throw CoreTestError.failed("应读取到恢复后的子任务")
        }
        try repository.setCompletion(reopenedChild, completed: true)
        let recompletedParent = try repository.fetch(id: parent.id)
        try expect(recompletedParent?.isDone == true, "全部子任务完成后应自动完成主任务")

        let newChild = WorkItem.create(month: "2026-07", title: "新增子任务", parentId: parent.id, level: 1)
        try repository.insertChild(newChild)
        let parentWithNewChild = try repository.fetch(id: parent.id)
        try expect(parentWithNewChild?.isDone == false, "新增未完成子任务应恢复主任务")

        try repository.permanentlyDelete(newChild)
        let parentAfterDeletion = try repository.fetch(id: parent.id)
        try expect(parentAfterDeletion?.isDone == true, "删除最后一个未完成子任务后应重新计算主任务")
    }

    private static func testDailyBackupAndDatabaseRecovery() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkLogRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var backupURL: URL?
        do {
            let manager = DatabaseManager(dataFolderURL: folder, schedulesAutomaticBackup: false)
            try manager.database.execute("""
            INSERT INTO work_months (id, month, title, summary, created_at, updated_at)
            VALUES ('month', '2026-07', '2026-07 工作清单', '', 1, 1)
            """)
            try manager.database.execute("""
            INSERT INTO work_items (
                id, month, title, note, status, module, parent_id, level, sort_order,
                raw_text, started_at, completed_at, deleted_at, created_at, updated_at
            ) VALUES ('recoverable', '2026-07', '可恢复任务', '', 'todo', '未分类', NULL, 0, 1,
                      '', NULL, NULL, NULL, 1, 1)
            """)
            backupURL = try manager.createManualBackup()
            manager.scheduleDailyBackupIfNeeded()

            let timeout = Date().addingTimeInterval(2)
            while Date() < timeout {
                if try manager.availableBackups().contains(where: { $0.name.hasPrefix("worklog-daily-") }) {
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            let backups = try manager.availableBackups()
            guard let dailyBackup = backups.first(where: { $0.name.hasPrefix("worklog-daily-") }) else {
                throw CoreTestError.failed("后台每日备份应成功生成")
            }
            try manager.validateBackup(at: dailyBackup.url)
            manager.performMaintenance()
        }

        guard let backupURL else {
            throw CoreTestError.failed("应生成手动数据库备份")
        }
        Thread.sleep(forTimeInterval: 0.1)
        let databaseURL = folder.appendingPathComponent("worklog.sqlite")
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + suffix))
        }
        try Data("not a sqlite database".utf8).write(to: databaseURL, options: .atomic)

        let recoveryManager = DatabaseManager(dataFolderURL: folder, schedulesAutomaticBackup: false)
        try expect(recoveryManager.startupFailure != nil, "损坏数据库应进入恢复模式而不是崩溃")
        try recoveryManager.validateBackup(at: backupURL)
        let preservedURL = try recoveryManager.restoreDatabase(from: backupURL)
        try expect(recoveryManager.startupFailure == nil, "恢复成功后应退出恢复模式")
        try expect(preservedURL != nil && FileManager.default.fileExists(atPath: preservedURL!.path), "恢复前应保留故障数据库")

        let recoveredTitle = try recoveryManager.database.query(
            "SELECT title FROM work_items WHERE id = 'recoverable'"
        ).first?["title"]?.stringValue
        try expect(recoveredTitle == "可恢复任务", "恢复后应读取到备份中的任务")
        let recoveredDatabaseIsValid = try recoveryManager.database.quickCheck()
        try expect(recoveredDatabaseIsValid, "恢复后的数据库应通过完整性校验")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CoreTestError.failed(message) }
    }
}
