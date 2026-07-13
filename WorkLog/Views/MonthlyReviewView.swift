import SwiftUI

struct MonthlyReviewView: View {
    @EnvironmentObject private var app: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var monthItems: [WorkItem] = []

    private var doneItems: [WorkItem] {
        monthItems.filter { $0.status == .done }
    }

    private var todoItems: [WorkItem] {
        monthItems.filter { $0.status != .done }
    }

    private var progress: Double {
        guard !monthItems.isEmpty else { return 0 }
        return Double(doneItems.count) / Double(monthItems.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720)
        .frame(minHeight: 360)
        .onAppear {
            monthItems = app.fetchSelectedMonthItemsForDisplay()
        }
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

    private var content: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 28, weight: .bold))
                        Text("完成进度")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 118, height: 118)

                Text("\(doneItems.count) / \(monthItems.count)")
                    .font(.headline)
            }
            .frame(width: 170)

            Divider()

            reviewColumn(
                title: "已完成（\(doneItems.count)）",
                color: .green,
                symbolName: "checkmark.circle.fill",
                items: doneItems
            )

            Divider()

            reviewColumn(
                title: "未完成（\(todoItems.count)）",
                color: .orange,
                symbolName: "circle",
                items: todoItems
            )
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle")
                .foregroundColor(.accentColor)
            Text(reviewConclusion)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                app.copyMonthlySummary()
                dismiss()
            } label: {
                Label("复制复盘报告", systemImage: "doc.on.doc")
            }
        }
        .padding(18)
    }

    private var reviewConclusion: String {
        let modules = Array(Set(monthItems.map(\.module))).sorted().filter { !$0.isEmpty }
        guard !modules.isEmpty else {
            return "本月工作项已经整理，可继续补充分类和备注形成复盘记录。"
        }
        return "本月主要推进\(modules.prefix(4).joined(separator: "、"))分类，后续关注未完成事项收敛。"
    }

    private func reviewColumn(title: String, color: Color, symbolName: String, items: [WorkItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(items.prefix(5)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbolName)
                            .foregroundColor(color)
                        Text(item.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.subheadline)
                }

                if items.count > 5 {
                    Text("...")
                        .foregroundColor(.secondary)
                } else if items.isEmpty {
                    Text("暂无")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
    }
}
