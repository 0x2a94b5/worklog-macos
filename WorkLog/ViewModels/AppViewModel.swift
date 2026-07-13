import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()

    @Published var months: [WorkMonth] = []
    @Published var modules: [String] = []
    @Published var items: [WorkItem] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [WorkItem] = []
    @Published var searchFocusRequest: Int = 0
    @Published var selectedScope: SidebarScope
    @Published var selectedMonth: String
    @Published var selectedItemId: String?
    @Published var showImportSheet: Bool = false
    @Published var showMonthlyReviewSheet: Bool = false
    @Published var showDeleteConfirmation: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let monthRepository = WorkMonthRepository()
    private let itemRepository = WorkItemRepository()
    private var searchWorkItem: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "app.worklog.macos.search", qos: .userInitiated)
    private var knownCurrentMonth: String

    var selectedItem: WorkItem? {
        items.first { $0.id == selectedItemId }
    }

    var currentDoneCount: Int {
        items.filter { $0.status == .done }.count
    }

    var currentTotalCount: Int {
        items.count
    }

    var currentProgressText: String {
        "完成 \(currentDoneCount) / \(currentTotalCount)"
    }

    var currentProgress: Double {
        guard currentTotalCount > 0 else { return 0 }
        return Double(currentDoneCount) / Double(currentTotalCount)
    }

    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        let month = DateUtils.currentMonth()
        knownCurrentMonth = month
        selectedMonth = month
        selectedScope = .month(month)
        bootstrap()
    }

    func bootstrap() {
        do {
            try monthRepository.ensureMonth(selectedMonth)
            reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadAll() {
        do {
            months = try monthRepository.fetchAll()
            modules = try itemRepository.fetchModules()
            items = try itemRepository.fetch(scope: selectedScope)

            if selectedItemId == nil || !items.contains(where: { $0.id == selectedItemId }) {
                selectedItemId = items.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectScope(_ scope: SidebarScope) {
        selectedScope = scope
        if case let .month(month) = scope {
            selectedMonth = month
        }
        selectedItemId = nil
        reloadAll()
    }

    func selectItem(id: String?) {
        selectedItemId = id
    }

    func handleCalendarChange() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleCalendarChange()
            }
            return
        }

        let currentMonth = DateUtils.currentMonth()
        guard currentMonth != knownCurrentMonth || !months.contains(where: { $0.month == currentMonth }) else {
            return
        }

        let previousCurrentMonth = knownCurrentMonth
        let shouldFollowCurrentMonth = selectedScope == .month(previousCurrentMonth)
        knownCurrentMonth = currentMonth

        do {
            try monthRepository.ensureMonth(currentMonth)
            selectedMonth = currentMonth
            if shouldFollowCurrentMonth {
                selectedScope = .month(currentMonth)
                selectedItemId = nil
            }
            reloadAll()
            statusMessage = "已进入 \(currentMonth)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDeleteSelectedItem() {
        guard selectedItem != nil else { return }
        showDeleteConfirmation = true
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchWorkItem?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearch(expectedQuery: trimmed)
        }
        searchWorkItem = workItem
        searchQueue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func clearSearch() {
        searchWorkItem?.cancel()
        searchQuery = ""
        searchResults = []
    }

    func selectSearchResult(_ item: WorkItem) {
        clearSearch()
        selectedMonth = item.month
        selectedScope = .month(item.month)
        selectedItemId = nil
        reloadAll()
        selectItem(id: item.id)
    }

    func canReorderItem(sourceId: String, targetId: String) -> Bool {
        guard case .month = selectedScope,
              sourceId != targetId,
              let source = items.first(where: { $0.id == sourceId }),
              let target = items.first(where: { $0.id == targetId })
        else { return false }
        return source.month == target.month && source.parentId == target.parentId
    }

    func reorderItem(sourceId: String, targetId: String) {
        guard canReorderItem(sourceId: sourceId, targetId: targetId) else { return }
        let selectionId = selectedItemId
        do {
            try itemRepository.reorder(itemId: sourceId, to: targetId)
            selectedItemId = selectionId
            reloadAll()
            statusMessage = "已调整任务顺序"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createEmptyItem() {
        addQuickItem(title: "新工作项")
    }

    func addQuickItem(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try monthRepository.ensureMonth(selectedMonth)
            let parsed = MarkdownParser.parse(trimmed, fallbackMonth: selectedMonth)
            let nextSort = (try? itemRepository.nextSortOrder(month: selectedMonth)) ?? ((items.map(\.sortOrder).max() ?? 0) + 1)

            let newItems: [WorkItem]
            if parsed.items.isEmpty {
                newItems = [WorkItem.create(
                    month: selectedMonth,
                    title: trimmed,
                    status: .todo,
                    module: ModuleInferer.infer(from: trimmed),
                    sortOrder: nextSort,
                    rawText: trimmed
                )]
            } else {
                newItems = parsed.items.enumerated().map { offset, item in
                    var newItem = item
                    newItem.month = selectedMonth
                    newItem.sortOrder = nextSort + offset
                    return newItem
                }
            }

            try itemRepository.insertMany(newItems)
            selectedScope = .month(selectedMonth)
            reloadAll()
            selectedItemId = newItems.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedItem(undoManager: UndoManager? = nil) {
        guard let item = selectedItem else { return }
        do {
            let deletedItems = try itemRepository.deletionGroup(for: item)
            try itemRepository.permanentlyDelete(item)
            selectedItemId = nil
            reloadAll()
            statusMessage = "任务已删除"
            registerRestoreUndo(for: deletedItems, undoManager: undoManager)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addChildItem(to parent: WorkItem, title: String) -> WorkItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, parent.parentId == nil else { return nil }

        do {
            let sortOrder = try itemRepository.nextSortOrder(month: parent.month)
            let child = WorkItem.create(
                month: parent.month,
                title: trimmed,
                status: .todo,
                module: parent.module.isEmpty ? ModuleInferer.infer(from: trimmed) : parent.module,
                parentId: parent.id,
                level: parent.level + 1,
                sortOrder: sortOrder,
                rawText: "   - [ ] \(trimmed)"
            )
            try itemRepository.insert(child)
            selectedItemId = child.id
            reloadAll()
            return child
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleDone(_ item: WorkItem) {
        toggleDone(item, keepSelectionId: nil)
    }

    func toggleDone(_ item: WorkItem, keepSelectionId: String?) {
        var newItem = item
        if item.status == .done {
            newItem.status = .todo
            newItem.completedAt = nil
        } else {
            newItem.status = .done
            newItem.completedAt = DateUtils.nowTimestamp()
        }
        saveItem(newItem, keepSelectionId: keepSelectionId)
    }

    func toggleDone(itemId: String) {
        toggleDone(itemId: itemId, keepSelectionId: nil)
    }

    func toggleDone(itemId: String, keepSelectionId: String?) {
        do {
            guard let item = try itemRepository.fetch(id: itemId) else { return }
            toggleDone(item, keepSelectionId: keepSelectionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateItem(itemId: String, title: String, module: String, keepSelectionId: String? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        do {
            guard var item = try itemRepository.fetch(id: itemId) else { return }
            item.title = trimmedTitle
            let trimmedModule = module.trimmingCharacters(in: .whitespacesAndNewlines)
            item.module = trimmedModule.isEmpty ? ModuleInferer.infer(from: trimmedTitle) : trimmedModule
            saveItem(item, keepSelectionId: keepSelectionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func importMarkdown(_ markdown: String) -> Bool {
        do {
            let parsed = MarkdownParser.parse(markdown, fallbackMonth: selectedMonth)
            guard DateUtils.isValidMonth(parsed.month) else { throw MarkdownImportError.invalidMonth }
            guard !parsed.items.isEmpty else { throw MarkdownImportError.empty }
            guard parsed.items.allSatisfy({ $0.month == parsed.month }) else { throw MarkdownImportError.multipleMonths }
            try monthRepository.ensureMonth(parsed.month)
            let nextSortOrder = try itemRepository.nextSortOrder(month: parsed.month)
            let items = parsed.items.enumerated().map { offset, item in
                var appendedItem = item
                appendedItem.sortOrder = nextSortOrder + offset
                return appendedItem
            }
            try itemRepository.insertMany(items)
            selectedMonth = parsed.month
            selectedScope = .month(parsed.month)
            selectedItemId = nil
            statusMessage = "已追加导入 \(items.count) 条工作项"
            reloadAll()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func previewMarkdownImport(_ markdown: String) -> ParsedWorkLog {
        MarkdownParser.parse(markdown, fallbackMonth: selectedMonth)
    }

    func exportCurrentMonthToFile() {
        do {
            let monthItems = try itemRepository.fetch(month: selectedMonth)
            let markdown = MarkdownParser.export(month: selectedMonth, items: monthItems)
            let panel = NSSavePanel()
            panel.title = "导出 Markdown"
            panel.nameFieldStringValue = "WorkLog-\(selectedMonth).md"
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "已导出 \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateMonthlySummary() -> String {
        let monthItems = fetchSelectedMonthItemsForDisplay()
        return generateMonthlySummary(items: monthItems)
    }

    func generateMonthlySummary(items summaryItems: [WorkItem]) -> String {
        let done = summaryItems.filter { $0.status == .done }.prefix(8).map { "- \($0.title)" }.joined(separator: "\n")
        let todo = summaryItems.filter { $0.status != .done }.prefix(8).map { "- \($0.title)" }.joined(separator: "\n")
        let moduleText = Array(Set(summaryItems.map(\.module))).sorted().joined(separator: "、")

        return """
        \(selectedMonth) 工作复盘

        完成率：\(summaryItems.filter { $0.status == .done }.count) / \(summaryItems.count)

        已完成：
        \(done.isEmpty ? "- 暂无" : done)

        未完成：
        \(todo.isEmpty ? "- 暂无" : todo)

        涉及分类：\(moduleText.isEmpty ? "未分类" : moduleText)
        """
    }

    func copyMonthlySummary() {
        let summary = generateMonthlySummary(items: fetchSelectedMonthItemsForDisplay())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        statusMessage = "已复制月度复盘到剪贴板"
    }

    func fetchSelectedMonthItemsForDisplay() -> [WorkItem] {
        do {
            return try itemRepository.fetch(month: selectedMonth)
        } catch {
            errorMessage = error.localizedDescription
            return items
        }
    }

    func openDataFolder() {
        let url = DatabaseManager.shared.databaseURL.deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    func createDatabaseBackup() {
        do {
            let url = try DatabaseManager.shared.createManualBackup()
            statusMessage = "已备份到 \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveItem(_ item: WorkItem, keepSelectionId: String? = nil) {
        do {
            try itemRepository.save(item)
            selectedItemId = keepSelectionId ?? item.id
            reloadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performSearch(expectedQuery: String) {
        do {
            let results = try itemRepository.search(expectedQuery, limit: 50)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == expectedQuery
                else { return }
                self.searchResults = results
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == expectedQuery
                else { return }
                self.searchResults = []
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func registerRestoreUndo(for items: [WorkItem], undoManager: UndoManager?) {
        guard let undoManager, !items.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(items, undoManager: undoManager)
        }
        undoManager.setActionName("删除任务")
    }

    private func restore(_ items: [WorkItem], undoManager: UndoManager) {
        do {
            try itemRepository.insertMany(items.sorted { $0.level < $1.level })
            selectedMonth = items[0].month
            selectedScope = .month(items[0].month)
            selectedItemId = items[0].id
            reloadAll()
            undoManager.registerUndo(withTarget: self) { target in
                target.deleteAgain(items, undoManager: undoManager)
            }
            undoManager.setActionName("删除任务")
            statusMessage = "已恢复任务"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAgain(_ items: [WorkItem], undoManager: UndoManager) {
        guard let root = items.first else { return }
        do {
            try itemRepository.permanentlyDelete(root)
            selectedItemId = nil
            reloadAll()
            registerRestoreUndo(for: items, undoManager: undoManager)
            statusMessage = "任务已删除"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
