import Foundation

final class WorkMonthRepository {
    private let db: SQLiteDatabase

    init(db: SQLiteDatabase = DatabaseManager.shared.database) {
        self.db = db
    }

    func fetchAll() throws -> [WorkMonth] {
        let rows = try db.query("""
            SELECT id, month, title, summary, created_at, updated_at
            FROM work_months
            ORDER BY month DESC
        """)
        return rows.compactMap(Self.mapRow)
    }

    func ensureMonth(_ month: String) throws {
        if try find(month: month) == nil {
            try insert(WorkMonth.create(month: month))
        }
    }

    func find(month: String) throws -> WorkMonth? {
        let rows = try db.query("""
            SELECT id, month, title, summary, created_at, updated_at
            FROM work_months
            WHERE month = ?
            LIMIT 1
        """, parameters: [.text(month)])
        return rows.first.flatMap(Self.mapRow)
    }

    func insert(_ workMonth: WorkMonth) throws {
        try db.execute("""
            INSERT INTO work_months (id, month, title, summary, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, parameters: [
            .text(workMonth.id),
            .text(workMonth.month),
            .text(workMonth.title),
            .text(workMonth.summary),
            .integer(workMonth.createdAt),
            .integer(workMonth.updatedAt)
        ])
    }

    func updateSummary(month: String, summary: String) throws {
        try db.execute("""
            UPDATE work_months
            SET summary = ?, updated_at = ?
            WHERE month = ?
        """, parameters: [
            .text(summary),
            .integer(DateUtils.nowTimestamp()),
            .text(month)
        ])
    }

    private static func mapRow(_ row: [String: SQLiteValue]) -> WorkMonth? {
        guard
            let id = row["id"]?.stringValue,
            let month = row["month"]?.stringValue,
            let title = row["title"]?.stringValue,
            let summary = row["summary"]?.stringValue,
            let createdAt = row["created_at"]?.int64Value,
            let updatedAt = row["updated_at"]?.int64Value
        else {
            return nil
        }

        return WorkMonth(id: id, month: month, title: title, summary: summary, createdAt: createdAt, updatedAt: updatedAt)
    }
}
