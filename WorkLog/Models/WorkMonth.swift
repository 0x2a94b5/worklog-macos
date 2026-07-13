import Foundation

struct WorkMonth: Identifiable, Equatable {
    var id: String
    var month: String
    var title: String
    var summary: String
    var createdAt: Int64
    var updatedAt: Int64

    static func create(month: String) -> WorkMonth {
        let now = DateUtils.nowTimestamp()
        return WorkMonth(
            id: UUID().uuidString,
            month: month,
            title: "\(month) 工作清单",
            summary: "",
            createdAt: now,
            updatedAt: now
        )
    }
}
