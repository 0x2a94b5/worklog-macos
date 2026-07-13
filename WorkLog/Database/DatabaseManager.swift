import Foundation

final class DatabaseManager {
    static let shared = DatabaseManager()

    let database: SQLiteDatabase
    let databaseURL: URL

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let folderURL = appSupportURL.appendingPathComponent("WorkLog", isDirectory: true)
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }

            databaseURL = folderURL.appendingPathComponent("worklog.sqlite")
            let databaseExisted = fileManager.fileExists(atPath: databaseURL.path)
            database = try SQLiteDatabase(path: databaseURL.path)

            if databaseExisted {
                let version = try database.query("PRAGMA user_version").first?["user_version"]?.intValue ?? 0
                if version < 3 {
                    _ = try createBackup(kind: "pre-migration-\(DateUtils.fileSafeTimestamp())", retainCount: 5)
                }
            }

            try DatabaseMigrator.migrate(database)
            try createDailyBackupIfNeeded()

            print("WorkLog SQLite path: \(databaseURL.path)")
        } catch {
            fatalError("Database initialization failed: \(error.localizedDescription)")
        }
    }

    func performMaintenance() {
        do {
            try database.performMaintenance()
        } catch {
            print("WorkLog SQLite maintenance failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createManualBackup() throws -> URL {
        try createBackup(kind: "manual-\(DateUtils.fileSafeTimestamp())", retainCount: 20)
    }

    private func createDailyBackupIfNeeded() throws {
        let day = String(DateUtils.fileSafeTimestamp().prefix(8))
        let backupURL = backupFolderURL.appendingPathComponent("worklog-daily-\(day).sqlite")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try FileManager.default.createDirectory(at: backupFolderURL, withIntermediateDirectories: true)
        try database.backup(to: backupURL)
        try pruneBackups(prefix: "worklog-daily-", retainCount: 14)
    }

    @discardableResult
    private func createBackup(kind: String, retainCount: Int) throws -> URL {
        try FileManager.default.createDirectory(at: backupFolderURL, withIntermediateDirectories: true)
        let backupURL = backupFolderURL.appendingPathComponent("worklog-\(kind).sqlite")
        try? FileManager.default.removeItem(at: backupURL)
        try database.backup(to: backupURL)
        try pruneBackups(prefix: "worklog-\(kind.components(separatedBy: "-").first ?? kind)-", retainCount: retainCount)
        return backupURL
    }

    private var backupFolderURL: URL {
        databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Database", isDirectory: true)
    }

    private func pruneBackups(prefix: String, retainCount: Int) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: backupFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let matching = urls.filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
        for url in matching.dropFirst(retainCount) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
