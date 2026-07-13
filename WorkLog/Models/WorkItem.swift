import Foundation

struct WorkItem: Identifiable, Equatable {
    var id: String
    var month: String
    var title: String
    var note: String
    var status: WorkItemStatus
    var module: String
    var parentId: String?
    var level: Int
    var sortOrder: Int
    var rawText: String
    var startedAt: Int64?
    var completedAt: Int64?
    var deletedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64

    var isDone: Bool {
        status == .done
    }

    var numberedPrefix: String? {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = text.firstIndex(of: ".") else { return nil }
        let prefix = text[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return nil }
        return String(prefix)
    }

    var isNumberedTopic: Bool {
        parentId == nil && numberedPrefix != nil
    }

    static func create(
        month: String,
        title: String,
        status: WorkItemStatus = .todo,
        module: String = "",
        parentId: String? = nil,
        level: Int = 0,
        sortOrder: Int = 0,
        rawText: String = ""
    ) -> WorkItem {
        let now = DateUtils.nowTimestamp()
        return WorkItem(
            id: UUID().uuidString,
            month: month,
            title: title,
            note: "",
            status: status,
            module: module,
            parentId: parentId,
            level: level,
            sortOrder: sortOrder,
            rawText: rawText,
            startedAt: nil,
            completedAt: status == .done ? now : nil,
            deletedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum WorkItemStatus: String, CaseIterable, Identifiable {
    case todo
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "未完成"
        case .done: return "已完成"
        }
    }

    var symbolName: String {
        switch self {
        case .todo: return "circle"
        case .done: return "checkmark.circle.fill"
        }
    }
}
