import SwiftUI

struct MonthlyReviewView: View {
    @EnvironmentObject private var app: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var monthItems: [WorkItem] = []
    @State private var loadError: String?
    @State private var copyFeedback: CopyFeedback?
    @State private var selectedStatus: ReviewStatus = .todo

    private var primaryItems: [WorkItem] {
        monthItems.filter { $0.parentId == nil }
    }

    private var doneItems: [WorkItem] {
        primaryItems.filter(\.isDone)
    }

    private var todoItems: [WorkItem] {
        primaryItems.filter { !$0.isDone }
    }

    private var progress: Double {
        guard !primaryItems.isEmpty else { return 0 }
        return Double(doneItems.count) / Double(primaryItems.count)
    }

    private var visibleItems: [WorkItem] {
        selectedStatus == .todo ? todoItems : doneItems
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .onAppear(perform: loadMonthItems)
    }

    private var header: some View {
        HStack {
            Text("月度复盘")
                .font(.headline)
            Spacer()
            Text(app.selectedMonth)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            errorContent(loadError)
        } else {
            reviewContent
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            progressSummary

            Picker("任务状态", selection: $selectedStatus) {
                Text("未完成（\(todoItems.count)）")
                    .tag(ReviewStatus.todo)
                Text("已完成（\(doneItems.count)）")
                    .tag(ReviewStatus.done)
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            taskList
        }
        .padding(20)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 24, weight: .bold))

                Text("主任务 \(doneItems.count) / \(primaryItems.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(todoItems.isEmpty ? "全部完成" : "剩余 \(todoItems.count) 项")
                    .font(.subheadline)
                    .foregroundColor(todoItems.isEmpty ? .green : .orange)
            }

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("主任务完成进度")
            .accessibilityValue("\(doneItems.count) / \(primaryItems.count)，\(Int(progress * 100))%")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.accentColor)

                Text(loadError == nil
                     ? MonthlySummaryFormatter.conclusion(items: monthItems)
                     : "月度数据加载失败，请重试后再生成复盘报告。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if let copyFeedback {
                    Label(copyFeedback.message, systemImage: copyFeedback.symbolName)
                        .font(.caption)
                        .foregroundColor(copyFeedback.isSuccess ? .green : .red)
                }

                Spacer()

                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    copyReport()
                } label: {
                    Label("复制复盘报告", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(loadError != nil)
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var taskList: some View {
        if visibleItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: selectedStatus == .todo ? "checkmark.circle" : "tray")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text(selectedStatus == .todo ? "本月没有未完成任务" : "本月暂无已完成任务")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selectedStatus.symbolName)
                                .foregroundColor(selectedStatus.color)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .help(item.title)

                                if let progressText = childProgressText(for: item) {
                                    Text(progressText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            }
            .systemScrollerBehavior()
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text("无法加载月度复盘")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button("重试", action: loadMonthItems)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func childProgressText(for item: WorkItem) -> String? {
        let children = monthItems.filter { $0.parentId == item.id }
        guard !children.isEmpty else { return nil }
        return "子任务 \(children.filter(\.isDone).count) / \(children.count)"
    }

    private func loadMonthItems() {
        do {
            let loadedItems = try app.fetchSelectedMonthItemsForDisplay()
            let loadedPrimaryItems = loadedItems.filter { $0.parentId == nil }
            let hasTodoItems = loadedPrimaryItems.contains { !$0.isDone }
            let hasDoneItems = loadedPrimaryItems.contains { $0.isDone }

            monthItems = loadedItems
            loadError = nil
            copyFeedback = nil
            selectedStatus = !hasTodoItems && hasDoneItems ? .done : .todo
        } catch {
            monthItems = []
            loadError = error.localizedDescription
            copyFeedback = nil
        }
    }

    private func copyReport() {
        if app.copyMonthlySummary(items: monthItems) {
            copyFeedback = CopyFeedback(message: "已复制到剪贴板", symbolName: "checkmark.circle.fill", isSuccess: true)
        } else {
            copyFeedback = CopyFeedback(message: "复制失败，请重试", symbolName: "exclamationmark.circle.fill", isSuccess: false)
        }
    }
}

private enum ReviewStatus {
    case todo
    case done

    var symbolName: String {
        switch self {
        case .todo: return "circle"
        case .done: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .todo: return .orange
        case .done: return .green
        }
    }
}

private struct CopyFeedback {
    let message: String
    let symbolName: String
    let isSuccess: Bool
}
