import Foundation

enum MonthlySummaryFormatter {
    static func report(month: String, items: [WorkItem]) -> String {
        let primaryItems = items.filter { $0.parentId == nil }
        let doneItems = primaryItems.filter(\.isDone)
        let todoItems = primaryItems.filter { !$0.isDone }
        let done = hierarchicalLines(for: doneItems, allItems: items)
        let todo = hierarchicalLines(for: todoItems, allItems: items)
        let moduleText = modules(in: items).joined(separator: "、")

        return """
        \(month) 工作复盘

        主任务完成率：\(doneItems.count) / \(primaryItems.count)

        已完成：
        \(done.isEmpty ? "- 暂无" : done)

        未完成：
        \(todo.isEmpty ? "- 暂无" : todo)

        涉及分类：\(moduleText.isEmpty ? "未分类" : moduleText)

        复盘结论：\(conclusion(items: items))
        """
    }

    static func conclusion(items: [WorkItem]) -> String {
        let primaryItems = items.filter { $0.parentId == nil }
        let doneCount = primaryItems.filter(\.isDone).count
        let todoCount = primaryItems.count - doneCount

        let progressText: String
        if primaryItems.isEmpty {
            progressText = "本月暂无主任务，可返回清单添加后再生成复盘。"
        } else if todoCount == 0 {
            progressText = "本月 \(primaryItems.count) 项主任务已全部完成。"
        } else if doneCount == 0 {
            progressText = "本月共有 \(todoCount) 项主任务待完成，建议优先确定后续处理顺序。"
        } else {
            progressText = "本月完成 \(doneCount) / \(primaryItems.count) 项主任务，剩余 \(todoCount) 项待继续跟进。"
        }

        let moduleNames = modules(in: items)
        guard !moduleNames.isEmpty else { return progressText }
        let visibleModules = moduleNames.prefix(4).joined(separator: "、")
        let suffix = moduleNames.count > 4 ? "等" : ""
        return "\(progressText) 涉及分类：\(visibleModules)\(suffix)。"
    }

    private static func hierarchicalLines(for primaryItems: [WorkItem], allItems: [WorkItem]) -> String {
        primaryItems.flatMap { item -> [String] in
            let parentLine = "- \(item.title)"
            let childLines = allItems
                .filter { $0.parentId == item.id }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { child in
                    "  - [\(child.isDone ? "x" : " ")] \(child.title)"
                }
            return [parentLine] + childLines
        }
        .joined(separator: "\n")
    }

    private static func modules(in items: [WorkItem]) -> [String] {
        Array(Set(items.compactMap { item in
            let module = item.module.trimmingCharacters(in: .whitespacesAndNewlines)
            return module.isEmpty ? nil : module
        })).sorted()
    }
}
