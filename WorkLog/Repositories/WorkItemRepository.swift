import Foundation

struct WorkItemHierarchyState {
    struct SortState {
        let itemId: String
        let sortOrder: Int
    }

    struct ParentCompletionState {
        let itemId: String
        let status: WorkItemStatus
        let completedAt: Int64?
        let updatedAt: Int64
    }

    let sourceItem: WorkItem
    let sortStates: [SortState]
    let parentCompletionStates: [ParentCompletionState]

    var focusedItemId: String { sourceItem.id }
}

enum WorkItemHierarchyError: Error, LocalizedError {
    case itemNotFound
    case invalidParent
    case differentMonth
    case nestedChildren

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "没有找到要调整的任务"
        case .invalidParent: return "只能选择同月一级任务作为父任务"
        case .differentMonth: return "不能跨月份调整任务层级"
        case .nestedChildren: return "该任务包含子任务，请先提升或移动现有子任务"
        }
    }
}

final class WorkItemRepository {
    private let db: SQLiteDatabase

    init(db: SQLiteDatabase = DatabaseManager.shared.database) {
        self.db = db
    }

    func fetch(scope: SidebarScope) throws -> [WorkItem] {
        switch scope {
        case .month(let month):
            return try fetchWhere("month = ?", [.text(month)])
        case .module(let module):
            return try fetchWhere("module = ?", [.text(module)])
        case .status(let status):
            return try fetchWhere("status = ?", [.text(status.rawValue)])
        }
    }

    func fetch(month: String) throws -> [WorkItem] {
        try fetchWhere("month = ?", [.text(month)])
    }

    func fetch(id: String) throws -> WorkItem? {
        try fetchWhere("id = ?", [.text(id)]).first
    }

    func fetchChildren(parentId: String) throws -> [WorkItem] {
        try fetchWhere("parent_id = ?", [.text(parentId)])
    }

    func search(_ query: String, limit: Int = 50) throws -> [WorkItem] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        let rows = try db.query("""
            SELECT id, month, title, note, status, module, parent_id,
                   level, sort_order, raw_text, started_at, completed_at, deleted_at, created_at, updated_at
            FROM work_items
            WHERE deleted_at IS NULL AND (
                   title LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR note LIKE ? ESCAPE '\\' COLLATE NOCASE
                OR module LIKE ? ESCAPE '\\' COLLATE NOCASE
            )
            ORDER BY
                CASE status WHEN 'todo' THEN 0 ELSE 1 END,
                month DESC,
                updated_at DESC
            LIMIT ?
        """, parameters: [
            .text(pattern), .text(pattern), .text(pattern),
            .integer(Int64(limit))
        ])
        return rows.compactMap(Self.mapRow)
    }

    func fetchModules() throws -> [String] {
        let rows = try db.query("""
            SELECT module, MAX(updated_at) AS last_used_at
            FROM work_items
            WHERE module != '' AND deleted_at IS NULL
            GROUP BY module
            ORDER BY last_used_at DESC, module COLLATE NOCASE ASC
        """)
        return rows.compactMap { $0["module"]?.stringValue }
    }

    func count(month: String, status: WorkItemStatus? = nil) throws -> Int {
        if let status {
            let rows = try db.query("""
                SELECT COUNT(*) AS count
                FROM work_items
                WHERE month = ? AND status = ? AND deleted_at IS NULL
            """, parameters: [.text(month), .text(status.rawValue)])
            return rows.first?["count"]?.intValue ?? 0
        }

        let rows = try db.query("""
            SELECT COUNT(*) AS count
            FROM work_items
            WHERE month = ? AND deleted_at IS NULL
        """, parameters: [.text(month)])
        return rows.first?["count"]?.intValue ?? 0
    }

    func nextSortOrder(month: String) throws -> Int {
        let rows = try db.query("""
            SELECT COALESCE(MAX(sort_order), 0) AS sort_order
            FROM work_items
            WHERE month = ? AND deleted_at IS NULL
        """, parameters: [.text(month)])
        return (rows.first?["sort_order"]?.intValue ?? 0) + 1
    }

    func reorder(itemId: String, to targetId: String) throws {
        guard itemId != targetId,
              let item = try fetch(id: itemId),
              let target = try fetch(id: targetId),
              item.month == target.month,
              item.parentId == target.parentId
        else { return }

        var siblings: [WorkItem]
        if let parentId = item.parentId {
            siblings = try fetchChildren(parentId: parentId)
        } else {
            siblings = try fetchWhere("month = ? AND parent_id IS NULL", [.text(item.month)])
        }

        siblings.sort { $0.sortOrder < $1.sortOrder }
        guard let sourceIndex = siblings.firstIndex(where: { $0.id == itemId }),
              let targetIndex = siblings.firstIndex(where: { $0.id == targetId })
        else { return }

        let movingItem = siblings.remove(at: sourceIndex)
        siblings.insert(movingItem, at: min(targetIndex, siblings.count))

        try db.inTransaction {
            for (index, sibling) in siblings.enumerated() where sibling.sortOrder != index + 1 {
                try db.execute(
                    "UPDATE work_items SET sort_order = ? WHERE id = ?",
                    parameters: [.integer(Int64(index + 1)), .text(sibling.id)]
                )
            }
        }
    }

    @discardableResult
    func reparent(itemId: String, to newParentId: String?) throws -> WorkItemHierarchyState {
        guard var item = try fetch(id: itemId) else {
            throw WorkItemHierarchyError.itemNotFound
        }
        guard item.parentId != newParentId else {
            return hierarchyState(sourceItem: item, sortItems: [item], parentItems: [])
        }

        let oldParentId = item.parentId
        let targetParent: WorkItem?
        if let newParentId {
            guard newParentId != item.id,
                  let parent = try fetch(id: newParentId),
                  parent.parentId == nil
            else { throw WorkItemHierarchyError.invalidParent }
            guard parent.month == item.month else {
                throw WorkItemHierarchyError.differentMonth
            }
            if item.parentId == nil, !(try fetchChildren(parentId: item.id)).isEmpty {
                throw WorkItemHierarchyError.nestedChildren
            }
            targetParent = parent
        } else {
            guard oldParentId != nil else { throw WorkItemHierarchyError.invalidParent }
            targetParent = nil
        }

        let oldSiblings = try siblings(month: item.month, parentId: oldParentId)
        let destinationSiblings = try siblings(month: item.month, parentId: newParentId)
        var affectedParents: [WorkItem] = []
        if let oldParentId, let oldParent = try fetch(id: oldParentId) {
            affectedParents.append(oldParent)
        }
        if let targetParent { affectedParents.append(targetParent) }
        let state = hierarchyState(
            sourceItem: item,
            sortItems: oldSiblings + destinationSiblings,
            parentItems: affectedParents
        )

        let oldRemaining = oldSiblings.filter { $0.id != item.id }
        var destination = destinationSiblings.filter { $0.id != item.id }
        let destinationIndex: Int
        if newParentId == nil,
           let oldParentId,
           let parentIndex = destination.firstIndex(where: { $0.id == oldParentId }) {
            destinationIndex = parentIndex + 1
        } else {
            destinationIndex = destination.count
        }

        item.parentId = newParentId
        item.level = newParentId == nil ? 0 : 1
        if let targetParent {
            item.module = targetParent.module.isEmpty ? ModuleDefaults.uncategorized : targetParent.module
            item.rawText = "   - [\(item.isDone ? "x" : " ")] \(item.title)"
        } else {
            item.rawText = "[\(item.isDone ? "x" : " ")]\(item.title)"
        }
        item.updatedAt = DateUtils.nowTimestamp()
        destination.insert(item, at: min(destinationIndex, destination.count))

        try db.inTransaction {
            try updateHierarchy(item)
            try updateSortOrders(oldRemaining)
            try updateSortOrders(destination)
            if let oldParentId { try synchronizeParentCompletion(parentId: oldParentId) }
            if let newParentId { try synchronizeParentCompletion(parentId: newParentId) }
        }
        return state
    }

    @discardableResult
    func restoreHierarchyState(_ state: WorkItemHierarchyState) throws -> WorkItemHierarchyState {
        guard let currentSource = try fetch(id: state.sourceItem.id) else {
            throw WorkItemHierarchyError.itemNotFound
        }
        let currentSortItems = try state.sortStates.compactMap { try fetch(id: $0.itemId) }
        let currentParentItems = try state.parentCompletionStates.compactMap { try fetch(id: $0.itemId) }
        let inverseState = hierarchyState(
            sourceItem: currentSource,
            sortItems: currentSortItems,
            parentItems: currentParentItems
        )

        try db.inTransaction {
            try updateHierarchy(state.sourceItem)
            try restoreSortStates(state.sortStates)
            try restoreParentCompletionStates(state.parentCompletionStates)
        }
        return inverseState
    }

    func insert(_ item: WorkItem) throws {
        try db.execute("""
            INSERT INTO work_items (
                id, month, title, note, status, module, parent_id,
                level, sort_order, raw_text, started_at, completed_at, deleted_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, parameters: parameters(for: item))
    }

    func insertChild(_ child: WorkItem) throws {
        guard let parentId = child.parentId else {
            try insert(child)
            return
        }

        try db.inTransaction {
            try insert(child)
            try synchronizeParentCompletion(parentId: parentId)
        }
    }

    func save(_ item: WorkItem) throws {
        var newItem = item
        newItem.updatedAt = DateUtils.nowTimestamp()

        try db.execute("""
            UPDATE work_items
            SET month = ?, title = ?, note = ?, status = ?, module = ?, parent_id = ?,
                level = ?, sort_order = ?, raw_text = ?, started_at = ?, completed_at = ?, updated_at = ?
            WHERE id = ? AND deleted_at IS NULL
        """, parameters: [
            .text(newItem.month),
            .text(newItem.title),
            .text(newItem.note),
            .text(newItem.status.rawValue),
            .text(newItem.module),
            newItem.parentId.map(SQLiteValue.text) ?? .null,
            .integer(Int64(newItem.level)),
            .integer(Int64(newItem.sortOrder)),
            .text(newItem.rawText),
            newItem.startedAt.map(SQLiteValue.integer) ?? .null,
            newItem.completedAt.map(SQLiteValue.integer) ?? .null,
            .integer(newItem.updatedAt),
            .text(newItem.id)
        ])
    }

    func permanentlyDelete(_ item: WorkItem) throws {
        let rootId = item.id
        try db.inTransaction {
            try db.execute("DELETE FROM work_items WHERE id = ? OR parent_id = ?", parameters: [.text(rootId), .text(rootId)])
            if let parentId = item.parentId {
                try synchronizeParentCompletion(parentId: parentId)
            }
        }
    }

    func insertMany(_ items: [WorkItem]) throws {
        try db.inTransaction {
            for item in items {
                try insert(item)
            }
            for parentId in Set(items.compactMap(\.parentId)) {
                try synchronizeParentCompletion(parentId: parentId)
            }
        }
    }

    func setCompletion(_ item: WorkItem, completed: Bool) throws {
        let status: WorkItemStatus = completed ? .done : .todo
        let timestamp = DateUtils.nowTimestamp()

        try db.inTransaction {
            try updateCompletion(id: item.id, status: status, timestamp: timestamp)

            if item.parentId == nil {
                for child in try fetchChildren(parentId: item.id) {
                    try updateCompletion(id: child.id, status: status, timestamp: timestamp)
                }
            } else if let parentId = item.parentId {
                try synchronizeParentCompletion(parentId: parentId, timestamp: timestamp)
            }
        }
    }

    func synchronizeParentStatuses() throws {
        let rows = try db.query("""
            SELECT DISTINCT parent_id
            FROM work_items
            WHERE parent_id IS NOT NULL AND deleted_at IS NULL
        """)
        let parentIds = rows.compactMap { $0["parent_id"]?.stringValue }
        try db.inTransaction {
            for parentId in parentIds {
                try synchronizeParentCompletion(parentId: parentId)
            }
        }
    }

    func deletionGroup(for item: WorkItem) throws -> [WorkItem] {
        if item.parentId == nil {
            return [item] + (try fetchChildren(parentId: item.id))
        }
        return [item]
    }

    private func synchronizeParentCompletion(parentId: String, timestamp: Int64 = DateUtils.nowTimestamp()) throws {
        let children = try fetchChildren(parentId: parentId)
        guard !children.isEmpty, let parent = try fetch(id: parentId) else { return }

        let status: WorkItemStatus = children.allSatisfy(\.isDone) ? .done : .todo
        guard parent.status != status else { return }
        try updateCompletion(id: parentId, status: status, timestamp: timestamp)
    }

    private func siblings(month: String, parentId: String?) throws -> [WorkItem] {
        let items: [WorkItem]
        if let parentId {
            items = try fetchChildren(parentId: parentId)
        } else {
            items = try fetchWhere("month = ? AND parent_id IS NULL", [.text(month)])
        }
        return items.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func hierarchyState(
        sourceItem: WorkItem,
        sortItems: [WorkItem],
        parentItems: [WorkItem]
    ) -> WorkItemHierarchyState {
        var seen = Set<String>()
        let sortStates = sortItems.compactMap { item -> WorkItemHierarchyState.SortState? in
            guard seen.insert(item.id).inserted else { return nil }
            return .init(itemId: item.id, sortOrder: item.sortOrder)
        }
        seen.removeAll()
        let parentStates = parentItems.compactMap { item -> WorkItemHierarchyState.ParentCompletionState? in
            guard seen.insert(item.id).inserted else { return nil }
            return .init(
                itemId: item.id,
                status: item.status,
                completedAt: item.completedAt,
                updatedAt: item.updatedAt
            )
        }
        return WorkItemHierarchyState(
            sourceItem: sourceItem,
            sortStates: sortStates,
            parentCompletionStates: parentStates
        )
    }

    private func updateSortOrders(_ items: [WorkItem]) throws {
        for (index, item) in items.enumerated() where item.sortOrder != index + 1 {
            try db.execute(
                "UPDATE work_items SET sort_order = ? WHERE id = ? AND deleted_at IS NULL",
                parameters: [.integer(Int64(index + 1)), .text(item.id)]
            )
        }
    }

    private func updateHierarchy(_ item: WorkItem) throws {
        try db.execute("""
            UPDATE work_items
            SET module = ?, parent_id = ?, level = ?, sort_order = ?, raw_text = ?, updated_at = ?
            WHERE id = ? AND deleted_at IS NULL
        """, parameters: [
            .text(item.module),
            item.parentId.map(SQLiteValue.text) ?? .null,
            .integer(Int64(item.level)),
            .integer(Int64(item.sortOrder)),
            .text(item.rawText),
            .integer(item.updatedAt),
            .text(item.id)
        ])
    }

    private func restoreSortStates(_ states: [WorkItemHierarchyState.SortState]) throws {
        for state in states {
            try db.execute(
                "UPDATE work_items SET sort_order = ? WHERE id = ? AND deleted_at IS NULL",
                parameters: [.integer(Int64(state.sortOrder)), .text(state.itemId)]
            )
        }
    }

    private func restoreParentCompletionStates(
        _ states: [WorkItemHierarchyState.ParentCompletionState]
    ) throws {
        for state in states {
            try db.execute("""
                UPDATE work_items
                SET status = ?, completed_at = ?, updated_at = ?
                WHERE id = ? AND deleted_at IS NULL
            """, parameters: [
                .text(state.status.rawValue),
                state.completedAt.map(SQLiteValue.integer) ?? .null,
                .integer(state.updatedAt),
                .text(state.itemId)
            ])
        }
    }

    private func updateCompletion(id: String, status: WorkItemStatus, timestamp: Int64) throws {
        try db.execute("""
            UPDATE work_items
            SET status = ?, completed_at = ?, updated_at = ?
            WHERE id = ? AND deleted_at IS NULL
        """, parameters: [
            .text(status.rawValue),
            status == .done ? .integer(timestamp) : .null,
            .integer(timestamp),
            .text(id)
        ])
    }

    private func fetchWhere(_ condition: String, _ parameters: [SQLiteValue], includeDeleted: Bool = false) throws -> [WorkItem] {
        let visibilityCondition = includeDeleted ? "deleted_at IS NOT NULL" : "deleted_at IS NULL"
        let rows = try db.query("""
            SELECT id, month, title, note, status, module, parent_id,
                   level, sort_order, raw_text, started_at, completed_at, deleted_at, created_at, updated_at
            FROM work_items
            WHERE (\(condition)) AND \(visibilityCondition)
            ORDER BY COALESCE(deleted_at, 0) DESC, month DESC, sort_order ASC, created_at ASC
        """, parameters: parameters)
        return rows.compactMap(Self.mapRow)
    }

    private func parameters(for item: WorkItem) -> [SQLiteValue] {
        [
            .text(item.id),
            .text(item.month),
            .text(item.title),
            .text(item.note),
            .text(item.status.rawValue),
            .text(item.module),
            item.parentId.map(SQLiteValue.text) ?? .null,
            .integer(Int64(item.level)),
            .integer(Int64(item.sortOrder)),
            .text(item.rawText),
            item.startedAt.map(SQLiteValue.integer) ?? .null,
            item.completedAt.map(SQLiteValue.integer) ?? .null,
            item.deletedAt.map(SQLiteValue.integer) ?? .null,
            .integer(item.createdAt),
            .integer(item.updatedAt)
        ]
    }

    private static func mapRow(_ row: [String: SQLiteValue]) -> WorkItem? {
        guard
            let id = row["id"]?.stringValue,
            let month = row["month"]?.stringValue,
            let title = row["title"]?.stringValue,
            let note = row["note"]?.stringValue,
            let statusRaw = row["status"]?.stringValue,
            let status = WorkItemStatus(rawValue: statusRaw),
            let module = row["module"]?.stringValue,
            let level = row["level"]?.intValue,
            let sortOrder = row["sort_order"]?.intValue,
            let rawText = row["raw_text"]?.stringValue,
            let createdAt = row["created_at"]?.int64Value,
            let updatedAt = row["updated_at"]?.int64Value
        else {
            return nil
        }

        let parentId = row["parent_id"]?.stringValue
        let startedAt = row["started_at"]?.int64Value
        let completedAt = row["completed_at"]?.int64Value
        let deletedAt = row["deleted_at"]?.int64Value

        return WorkItem(
            id: id,
            month: month,
            title: title,
            note: note,
            status: status,
            module: module,
            parentId: parentId,
            level: level,
            sortOrder: sortOrder,
            rawText: rawText,
            startedAt: startedAt,
            completedAt: completedAt,
            deletedAt: deletedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
