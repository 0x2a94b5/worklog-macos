import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkListView: View {
    @EnvironmentObject private var app: AppViewModel
    @Environment(\.undoManager) private var undoManager
    @State private var quickTitle = ""
    @State private var collapsedItemIds: Set<String> = []
    @State private var draggingItemId: String?
    @State private var editingItemId: String?
    @State private var editingTitle = ""
    @State private var editingModule = ""
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isQuickAddFocused: Bool
    @State private var isListKeyboardActive = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if !app.isSearchActive {
                quickAddBar
            }
            Divider()
            if app.isSearchActive {
                searchResultList
            } else {
                itemList
            }
        }
        .onChange(of: app.searchFocusRequest) { _ in
            isListKeyboardActive = false
            isSearchFocused = true
        }
        .onChange(of: isSearchFocused) { focused in
            if focused { isListKeyboardActive = false }
        }
        .onChange(of: isQuickAddFocused) { focused in
            if focused { isListKeyboardActive = false }
        }
        .alert(isPresented: $app.showDeleteConfirmation) {
            Alert(
                title: Text("永久删除任务？"),
                message: Text("若为主任务，其子任务也会一并删除。删除后可使用 Command-Z 恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    cancelEditing()
                    app.deleteSelectedItem(undoManager: undoManager)
                },
                secondaryButton: .cancel()
            )
        }
        .onChange(of: app.isSearchActive) { active in
            if active { _ = commitEditing(keepSelectionId: app.selectedItemId) }
        }
        .onDisappear {
            _ = commitEditing(keepSelectionId: app.selectedItemId)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.isSearchActive ? "全局搜索" : titleText)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                searchField
            }

            HStack(spacing: 12) {
                Text(headerSummaryText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !app.isSearchActive {
                    ProgressView(value: app.currentProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 160)
                }

                Spacer()

                if let status = app.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索所有月份", text: Binding(
                get: { app.searchQuery },
                set: { app.updateSearchQuery($0) }
            ))
            .textFieldStyle(PlainTextFieldStyle())
            .focused($isSearchFocused)
            .onExitCommand {
                app.clearSearch()
                isSearchFocused = false
            }

            if app.isSearchActive {
                Button {
                    app.clearSearch()
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 150, idealWidth: 220, maxWidth: 220, minHeight: 28, maxHeight: 28)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSearchFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            TextField("添加工作项，按 Enter 保存", text: $quickTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isQuickAddFocused)
                .submitLabel(.done)
                .onSubmit(submitQuickAdd)

            Button(action: submitQuickAdd) {
                Label("添加", systemImage: "plus.circle.fill")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var itemList: some View {
        Group {
            if visibleItems.isEmpty {
                emptyState
            } else {
                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ScrollView {
                            ZStack(alignment: .topLeading) {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture(perform: commitEditingFromOutside)

                                LazyVStack(spacing: 0) {
                                    ForEach(visibleItems) { row in
                                        listRow(row)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .background(
                                                app.selectedItemId == row.item.id
                                                    ? Color.accentColor.opacity(0.16)
                                                    : Color.clear
                                            )
                                            .id(row.item.id)

                                        Divider()
                                            .padding(.leading, row.item.level == 0 ? 8 : 44)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                        }
                        .systemScrollerBehavior()
                        .onChange(of: app.selectedItemId) { itemId in
                            if editingItemId != nil, editingItemId != itemId {
                                _ = commitEditing(keepSelectionId: itemId)
                            }
                            revealAndScroll(to: itemId, proxy: proxy)
                        }
                    }
                }
            }
        }
        .background(
            WorkListKeyboardMonitor(
                isActive: isListKeyboardActive && editingItemId == nil,
                onMoveSelection: moveSelection,
                onDelete: app.requestDeleteSelectedItem,
                onToggleDone: toggleSelectedDone,
                onBeginEditing: beginEditingSelected
            )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("暂无工作项")
                .font(.headline)
            if case .month = app.selectedScope {
                Button {
                    app.createEmptyItem()
                } label: {
                    Label("新增工作项", systemImage: "plus")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultList: some View {
        Group {
            if app.searchResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("没有找到相关工作项")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(app.searchResults) { item in
                            Button {
                                app.selectSearchResult(item)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.status.symbolName)
                                        .foregroundColor(item.status == .done ? .secondary : .accentColor)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            Text(item.month)
                                            Text(item.status.title)
                                            if !item.module.isEmpty { Text(item.module) }
                                            if item.parentId != nil { Text("子任务") }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider()
                                .padding(.leading, 18)
                        }
                    }
                }
                .systemScrollerBehavior()
            }
        }
    }

    @ViewBuilder
    private func listRow(_ row: WorkListRow) -> some View {
        let content = WorkItemRowView(
            item: row.item,
            childCount: row.childCount,
            completedChildCount: row.completedChildCount,
            isCollapsed: collapsedItemIds.contains(row.item.id),
            isEditing: editingItemId == row.item.id,
            editingTitle: $editingTitle,
            editingModule: $editingModule,
            onToggleCollapse: row.childCount > 0 ? {
                toggleCollapse(row.item.id)
            } : nil,
            onBeginDrag: {
                draggingItemId = row.item.id
                return NSItemProvider(object: row.item.id as NSString)
            },
            onSelect: { selectRow(id: row.item.id) },
            onBeginEditing: { beginEditing(row.item) },
            onCommitEditing: { _ = commitEditing() },
            onCancelEditing: cancelEditing
        )
        .contextMenu {
            if row.item.parentId == nil {
                Button("新增子任务") { createChild(for: row.item) }
                Divider()
            }
            Button("修改标题") { beginEditing(row.item) }
            Divider()
            Button("删除") {
                selectRow(id: row.item.id)
                app.requestDeleteSelectedItem()
            }
        }

        if case .month = app.selectedScope {
            content
                .onDrop(
                    of: [UTType.text],
                    delegate: WorkItemDropDelegate(
                        draggingItemId: $draggingItemId,
                        canMove: { sourceId in
                            app.canReorderItem(sourceId: sourceId, targetId: row.item.id)
                        },
                        move: { sourceId in
                            app.reorderItem(sourceId: sourceId, targetId: row.item.id)
                        }
                    )
                )
        } else {
            WorkItemRowView(
                item: row.item,
                childCount: row.childCount,
                completedChildCount: row.completedChildCount,
                isCollapsed: collapsedItemIds.contains(row.item.id),
                isEditing: editingItemId == row.item.id,
                editingTitle: $editingTitle,
                editingModule: $editingModule,
                onToggleCollapse: nil,
                onBeginDrag: nil,
                onSelect: { selectRow(id: row.item.id) },
                onBeginEditing: { beginEditing(row.item) },
                onCommitEditing: { _ = commitEditing() },
                onCancelEditing: cancelEditing
            )
            .contextMenu {
                if row.item.parentId == nil {
                    Button("新增子任务") { createChild(for: row.item) }
                    Divider()
                }
                Button("修改标题") { beginEditing(row.item) }
                Divider()
                Button("删除") {
                    selectRow(id: row.item.id)
                    app.requestDeleteSelectedItem()
                }
            }
        }
    }

    private var visibleItems: [WorkListRow] {
        guard case .month = app.selectedScope else {
            return app.items.map { WorkListRow(item: $0, childCount: 0, completedChildCount: 0) }
        }

        var rows: [WorkListRow] = []
        let childrenByParent = Dictionary(grouping: app.items.filter { $0.parentId != nil }, by: { $0.parentId ?? "" })
        let parentItems = app.items
            .filter { $0.parentId == nil }
            .sorted { $0.sortOrder < $1.sortOrder }

        for item in parentItems {
            let children = (childrenByParent[item.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            rows.append(WorkListRow(
                item: item,
                childCount: children.count,
                completedChildCount: children.filter(\.isDone).count
            ))
            if !collapsedItemIds.contains(item.id) {
                rows.append(contentsOf: children.map {
                    WorkListRow(item: $0, childCount: 0, completedChildCount: 0)
                })
            }
        }

        return rows
    }

    private var titleText: String {
        switch app.selectedScope {
        case .month(let month): return "\(month) 工作清单"
        case .module(let module): return "\(module) 分类"
        case .status(let status): return status.title
        }
    }

    private var headerSummaryText: String {
        if app.isSearchActive { return "找到 \(app.searchResults.count) 条结果" }
        return app.currentProgressText
    }

    private func submitQuickAdd() {
        guard app.addQuickItem(title: quickTitle) else { return }
        quickTitle = ""
        DispatchQueue.main.async { isQuickAddFocused = true }
    }

    private func toggleCollapse(_ itemId: String) {
        if collapsedItemIds.contains(itemId) {
            collapsedItemIds.remove(itemId)
        } else {
            collapsedItemIds.insert(itemId)
        }
    }

    private func selectRow(id: String?) {
        if let editingItemId, editingItemId != id {
            guard commitEditing(keepSelectionId: id) else { return }
        }
        isSearchFocused = false
        isQuickAddFocused = false
        app.selectItem(id: id)
        isListKeyboardActive = true
    }

    private func commitEditingFromOutside() {
        guard editingItemId != nil else { return }
        _ = commitEditing(keepSelectionId: app.selectedItemId)
    }

    private func beginEditing(_ item: WorkItem) {
        if editingItemId != nil && editingItemId != item.id {
            guard commitEditing(keepSelectionId: item.id) else { return }
        }
        app.selectItem(id: item.id)
        editingTitle = item.title
        editingModule = item.module
        editingItemId = item.id
        isListKeyboardActive = false
    }

    @discardableResult
    private func commitEditing(keepSelectionId: String? = nil) -> Bool {
        guard let itemId = editingItemId else { return true }
        let title = editingTitle
        let module = editingModule
        guard app.updateItem(itemId: itemId, title: title, module: module, keepSelectionId: keepSelectionId) else {
            return false
        }
        editingItemId = nil
        editingTitle = ""
        editingModule = ""
        isListKeyboardActive = true
        return true
    }

    private func cancelEditing() {
        editingItemId = nil
        editingTitle = ""
        editingModule = ""
        isListKeyboardActive = true
    }

    private func createChild(for parent: WorkItem) {
        guard let child = app.addChildItem(to: parent, title: "新子任务") else { return }
        beginEditing(child)
    }

    private func revealAndScroll(to itemId: String?, proxy: ScrollViewProxy) {
        guard let itemId, let item = app.items.first(where: { $0.id == itemId }) else { return }
        if let parentId = item.parentId {
            collapsedItemIds.remove(parentId)
        }
        DispatchQueue.main.async {
            proxy.scrollTo(itemId, anchor: .center)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !visibleItems.isEmpty else { return }
        let currentIndex = app.selectedItemId.flatMap { selectedId in
            visibleItems.firstIndex(where: { $0.id == selectedId })
        }

        switch direction {
        case .up, .down:
            let offset = direction == .up ? -1 : 1
            let proposedIndex = (currentIndex ?? (offset > 0 ? -1 : visibleItems.count)) + offset
            let index = min(max(proposedIndex, 0), visibleItems.count - 1)
            app.selectItem(id: visibleItems[index].id)
        case .left:
            guard let item = app.selectedItem else { return }
            if let parentId = item.parentId {
                app.selectItem(id: parentId)
            } else if visibleItems.first(where: { $0.id == item.id })?.childCount ?? 0 > 0 {
                collapsedItemIds.insert(item.id)
            }
        case .right:
            guard let item = app.selectedItem, item.parentId == nil else { return }
            let children = app.items
                .filter { $0.parentId == item.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            guard let firstChild = children.first else { return }
            if collapsedItemIds.contains(item.id) {
                collapsedItemIds.remove(item.id)
            } else {
                app.selectItem(id: firstChild.id)
            }
        default:
            break
        }
    }

    private func toggleSelectedDone() {
        guard let item = app.selectedItem else { return }
        app.toggleDone(item, keepSelectionId: item.id)
    }

    private func beginEditingSelected() {
        guard let item = app.selectedItem else { return }
        beginEditing(item)
    }
}

private struct WorkListRow: Identifiable {
    let item: WorkItem
    let childCount: Int
    let completedChildCount: Int

    var id: String { item.id }
}

private struct WorkItemDropDelegate: DropDelegate {
    @Binding var draggingItemId: String?
    let canMove: (String) -> Bool
    let move: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggingItemId else { return false }
        return canMove(draggingItemId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let draggingItemId, canMove(draggingItemId) else {
            return DropProposal(operation: .cancel)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceId = draggingItemId, canMove(sourceId) else {
            draggingItemId = nil
            return false
        }
        move(sourceId)
        draggingItemId = nil
        return true
    }

}

private struct WorkListKeyboardMonitor: NSViewRepresentable {
    let isActive: Bool
    let onMoveSelection: (MoveCommandDirection) -> Void
    let onDelete: () -> Void
    let onToggleDone: () -> Void
    let onBeginEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onMoveSelection = onMoveSelection
        context.coordinator.onDelete = onDelete
        context.coordinator.onToggleDone = onToggleDone
        context.coordinator.onBeginEditing = onBeginEditing
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isActive = false
        var onMoveSelection: ((MoveCommandDirection) -> Void)?
        var onDelete: (() -> Void)?
        var onToggleDone: (() -> Void)?
        var onBeginEditing: (() -> Void)?
        weak var hostView: NSView?
        private var keyboardMonitor: Any?

        func installMonitor() {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isActive,
                      event.window === self.hostView?.window
                else { return event }
                if event.window?.firstResponder is NSTextView { return event }
                let commandModifiers = event.modifierFlags.intersection([.command, .option, .control])
                guard commandModifiers.isEmpty else { return event }

                switch event.keyCode {
                case 123:
                    self.onMoveSelection?(.left)
                    return nil
                case 124:
                    self.onMoveSelection?(.right)
                    return nil
                case 125:
                    self.onMoveSelection?(.down)
                    return nil
                case 126:
                    self.onMoveSelection?(.up)
                    return nil
                case 51, 117:
                    guard !event.isARepeat else { return nil }
                    self.onDelete?()
                    return nil
                case 49:
                    guard !event.isARepeat else { return nil }
                    self.onToggleDone?()
                    return nil
                case 36, 76:
                    guard !event.isARepeat else { return nil }
                    self.onBeginEditing?()
                    return nil
                default:
                    return event
                }
            }

        }

        func removeMonitor() {
            if let keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
                self.keyboardMonitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
