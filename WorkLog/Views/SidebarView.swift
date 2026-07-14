import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var app: AppViewModel
    @AppStorage("sidebar.showAllCategories") private var showAllCategories = false
    @AppStorage("sidebar.expandedYears") private var expandedYearsStorage = ""

    private let recentMonthLimit = 6
    private let frequentCategoryLimit = 8

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                appHeader
                statusSection
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    monthSection
                    if !app.modules.isEmpty {
                        categorySection
                    }
                }
                .padding(12)
            }
            .systemScrollerBehavior()

            Divider()

            Button {
                app.openDataFolder()
            } label: {
                Label("打开数据目录", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var appHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("WorkLog")
                    .font(.headline)
                Text("月度工作清单")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("状态")
            sidebarButton(title: "未完成", icon: "circle", scope: .status(.todo))
            sidebarButton(title: "已完成", icon: "checkmark.circle", scope: .status(.done))
        }
    }

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("月份")

            ForEach(Array(app.months.prefix(recentMonthLimit))) { month in
                monthButton(month)
            }

            ForEach(olderMonthGroups, id: \.year) { group in
                DisclosureGroup(isExpanded: yearExpansionBinding(group.year)) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(group.months) { month in
                            monthButton(month)
                        }
                    }
                    .padding(.top, 3)
                } label: {
                    Label("\(group.year) 年", systemImage: "archivebox")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("分类")

            ForEach(visibleCategories, id: \.self) { category in
                sidebarButton(title: category, icon: "folder", scope: .module(category))
            }

            if app.modules.count > frequentCategoryLimit {
                Button {
                    showAllCategories.toggle()
                } label: {
                    Label(
                        showAllCategories ? "收起分类" : "全部分类（\(app.modules.count)）",
                        systemImage: showAllCategories ? "chevron.up" : "ellipsis.circle"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
    }

    private var visibleCategories: [String] {
        showAllCategories ? app.modules : Array(app.modules.prefix(frequentCategoryLimit))
    }

    private var olderMonthGroups: [MonthGroup] {
        let olderMonths = Array(app.months.dropFirst(recentMonthLimit))
        let grouped = Dictionary(grouping: olderMonths) { month in
            String(month.month.prefix(4))
        }
        return grouped.keys.sorted(by: >).map { year in
            MonthGroup(year: year, months: grouped[year] ?? [])
        }
    }

    private func monthButton(_ month: WorkMonth) -> some View {
        sidebarButton(title: month.month, icon: "calendar", scope: .month(month.month))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
    }

    private func sidebarButton(title: String, icon: String, scope: SidebarScope) -> some View {
        let isSelected = app.selectedScope == scope
        return Button {
            app.selectScope(scope)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(isSelected ? .accentColor : .primary)
    }

    private func yearExpansionBinding(_ year: String) -> Binding<Bool> {
        Binding(
            get: { expandedYears.contains(year) },
            set: { isExpanded in
                var years = expandedYears
                if isExpanded {
                    years.insert(year)
                } else {
                    years.remove(year)
                }
                expandedYearsStorage = years.sorted().joined(separator: ",")
            }
        )
    }

    private var expandedYears: Set<String> {
        Set(expandedYearsStorage.split(separator: ",").map(String.init))
    }
}

private struct MonthGroup {
    let year: String
    let months: [WorkMonth]
}
