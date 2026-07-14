import AppKit
import Foundation

struct DatabaseStartupFailure: Equatable {
    let message: String
}

struct DatabaseBackupInfo: Identifiable, Equatable {
    let url: URL
    let modifiedAt: Date

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

final class DatabaseManager {
    static let shared = DatabaseManager()

    let databaseURL: URL
    private(set) var database: SQLiteDatabase
    private(set) var startupFailure: DatabaseStartupFailure?

    private let maintenanceQueue = DispatchQueue(label: "app.worklog.macos.database-maintenance", qos: .utility)

    init(dataFolderURL: URL? = nil, schedulesAutomaticBackup: Bool = true) {
        let folderURL = dataFolderURL ?? Self.configuredDataFolderURL()
        databaseURL = folderURL.appendingPathComponent("worklog.sqlite")
        database = Self.makeFallbackDatabase()

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let databaseExisted = FileManager.default.fileExists(atPath: databaseURL.path)
            let primaryDatabase = try SQLiteDatabase(path: databaseURL.path)
            database = primaryDatabase

            if databaseExisted {
                let version = try primaryDatabase.query("PRAGMA user_version").first?["user_version"]?.intValue ?? 0
                if version < DatabaseMigrator.currentVersion {
                    _ = try createBackup(
                        kind: "pre-migration-\(DateUtils.fileSafeTimestamp())",
                        retainCount: 5
                    )
                }
            }

            try DatabaseMigrator.migrate(primaryDatabase)
            if schedulesAutomaticBackup {
                scheduleDailyBackupIfNeeded()
            }
        } catch {
            database = Self.makeFallbackDatabase()
            startupFailure = DatabaseStartupFailure(message: error.localizedDescription)
        }
    }

    func scheduleDailyBackupIfNeeded() {
        guard startupFailure == nil else { return }
        maintenanceQueue.async { [weak self] in
            guard let self, self.startupFailure == nil else { return }
            do {
                try self.createDailyBackupIfNeeded()
            } catch {
                print("WorkLog daily backup failed: \(error.localizedDescription)")
            }
        }
    }

    func performMaintenance() {
        guard startupFailure == nil else { return }
        do {
            try database.performMaintenance()
        } catch {
            print("WorkLog SQLite maintenance failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createManualBackup() throws -> URL {
        guard startupFailure == nil else {
            throw SQLiteDatabaseError.backupFailed("数据库当前不可用")
        }
        return try createBackup(kind: "manual-\(DateUtils.fileSafeTimestamp())", retainCount: 20)
    }

    func availableBackups() throws -> [DatabaseBackupInfo] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupFolderURL.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(
            at: backupFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard url.pathExtension == "sqlite" else { return nil }
            let values = try url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return DatabaseBackupInfo(url: url, modifiedAt: values.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func validateBackup(at backupURL: URL) throws {
        try validateBackupLocation(backupURL)
        let backupDatabase = try SQLiteDatabase(path: backupURL.path, readOnly: true)
        guard try backupDatabase.quickCheck() else {
            throw SQLiteDatabaseError.backupFailed("备份完整性校验失败")
        }
        let version = try backupDatabase.query("PRAGMA user_version").first?["user_version"]?.intValue ?? 0
        guard version <= DatabaseMigrator.currentVersion else {
            throw SQLiteDatabaseError.backupFailed("备份数据库版本过高，当前 App 无法读取")
        }
    }

    @discardableResult
    func restoreDatabase(from backupURL: URL) throws -> URL? {
        guard startupFailure != nil else {
            throw SQLiteDatabaseError.backupFailed("仅能在数据库恢复模式下替换数据库")
        }
        try validateBackup(at: backupURL)

        let fileManager = FileManager.default
        let folderURL = databaseURL.deletingLastPathComponent()
        let stagingURL = folderURL.appendingPathComponent("worklog-restore-\(UUID().uuidString).sqlite")
        defer { try? fileManager.removeItem(at: stagingURL) }

        try fileManager.copyItem(at: backupURL, to: stagingURL)
        let stagingDatabase = try SQLiteDatabase(path: stagingURL.path, readOnly: true)
        guard try stagingDatabase.quickCheck() else {
            throw SQLiteDatabaseError.backupFailed("恢复副本完整性校验失败")
        }

        let preservedURL = try preserveFailedDatabaseIfNeeded()
        if fileManager.fileExists(atPath: databaseURL.path) {
            _ = try fileManager.replaceItemAt(databaseURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: databaseURL)
        }
        try removeDatabaseSidecars()

        let restoredDatabase = try SQLiteDatabase(path: databaseURL.path)
        try DatabaseMigrator.migrate(restoredDatabase)
        guard try restoredDatabase.quickCheck() else {
            throw SQLiteDatabaseError.backupFailed("恢复后的数据库完整性校验失败")
        }

        database = restoredDatabase
        startupFailure = nil
        scheduleDailyBackupIfNeeded()
        return preservedURL
    }

    func openDataFolder() {
        NSWorkspace.shared.open(databaseURL.deletingLastPathComponent())
    }

    private func createDailyBackupIfNeeded() throws {
        let day = String(DateUtils.fileSafeTimestamp().prefix(8))
        let backupURL = backupFolderURL.appendingPathComponent("worklog-daily-\(day).sqlite")
        try FileManager.default.createDirectory(at: backupFolderURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                try validateBackup(at: backupURL)
                return
            } catch {
                try preserveInvalidBackup(at: backupURL)
            }
        }
        try writeValidatedBackup(to: backupURL)
        try pruneBackups(prefix: "worklog-daily-", retainCount: 14)
    }

    @discardableResult
    private func createBackup(kind: String, retainCount: Int) throws -> URL {
        try FileManager.default.createDirectory(at: backupFolderURL, withIntermediateDirectories: true)
        let backupURL = backupFolderURL.appendingPathComponent("worklog-\(kind).sqlite")
        try writeValidatedBackup(to: backupURL)
        let prefix = kind.components(separatedBy: "-").first ?? kind
        try pruneBackups(prefix: "worklog-\(prefix)-", retainCount: retainCount)
        return backupURL
    }

    private func writeValidatedBackup(to backupURL: URL) throws {
        let fileManager = FileManager.default
        let stagingURL = backupFolderURL.appendingPathComponent(".worklog-backup-\(UUID().uuidString).sqlite")
        defer { try? fileManager.removeItem(at: stagingURL) }

        try database.backup(to: stagingURL)
        let stagingDatabase = try SQLiteDatabase(path: stagingURL.path, readOnly: true)
        guard try stagingDatabase.quickCheck() else {
            throw SQLiteDatabaseError.backupFailed("新备份未通过完整性校验")
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            _ = try fileManager.replaceItemAt(backupURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: backupURL)
        }
    }

    private func preserveInvalidBackup(at backupURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: recoveryFolderURL, withIntermediateDirectories: true)
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let preservedURL = recoveryFolderURL.appendingPathComponent(
            "\(backupURL.deletingPathExtension().lastPathComponent)-invalid-\(DateUtils.fileSafeTimestamp())-\(uniqueSuffix).sqlite"
        )
        try fileManager.moveItem(at: backupURL, to: preservedURL)
    }

    private var backupFolderURL: URL {
        databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Database", isDirectory: true)
    }

    private var recoveryFolderURL: URL {
        databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    private func validateBackupLocation(_ backupURL: URL) throws {
        let resolvedBackup = backupURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedFolder = backupFolderURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedBackup.deletingLastPathComponent() == resolvedFolder else {
            throw SQLiteDatabaseError.backupFailed("只能恢复 WorkLog 备份目录中的文件")
        }
        let values = try backupURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SQLiteDatabaseError.backupFailed("备份文件类型无效")
        }
    }

    private func preserveFailedDatabaseIfNeeded() throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }

        try fileManager.createDirectory(at: recoveryFolderURL, withIntermediateDirectories: true)
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let baseName = "worklog-failed-\(DateUtils.fileSafeTimestamp())-\(uniqueSuffix).sqlite"
        let preservedURL = recoveryFolderURL.appendingPathComponent(baseName)
        try fileManager.copyItem(at: databaseURL, to: preservedURL)

        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: preservedURL.path + suffix)
            try fileManager.copyItem(at: source, to: destination)
        }
        return preservedURL
    }

    private func removeDatabaseSidecars() throws {
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
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

    private static func configuredDataFolderURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["WORKLOG_DATA_DIRECTORY"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/WorkLog", isDirectory: true)
    }

    private static func makeFallbackDatabase() -> SQLiteDatabase {
        do {
            let database = try SQLiteDatabase(path: ":memory:")
            try DatabaseMigrator.migrate(database)
            return database
        } catch {
            preconditionFailure("Unable to initialize recovery database: \(error.localizedDescription)")
        }
    }
}
