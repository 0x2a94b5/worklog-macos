import Foundation

struct ParsedWorkLog {
    var month: String
    var items: [WorkItem]
}

enum MarkdownImportError: Error, LocalizedError {
    case empty
    case invalidMonth
    case multipleMonths

    var errorDescription: String? {
        switch self {
        case .empty: return "没有识别到可导入的工作项"
        case .invalidMonth: return "月份格式无效，请使用 yyyy-MM，例如 2026-07"
        case .multipleMonths: return "一次只能导入一个月份，请拆分后再导入"
        }
    }
}

enum MarkdownParser {
    static func parse(_ markdown: String, fallbackMonth: String = DateUtils.currentMonth()) -> ParsedWorkLog {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var month = fallbackMonth
        var items: [WorkItem] = []
        var currentParentId: String?
        var sortOrder = 0

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line != "---" else { continue }

            if let detectedMonth = detectMonth(from: line) {
                month = detectedMonth
                continue
            }

            if let parsed = parseChecklistLine(line) {
                sortOrder += 1
                let item = WorkItem.create(
                    month: month,
                    title: parsed.title,
                    status: parsed.isDone ? .done : .todo,
                    module: ModuleInferer.infer(from: parsed.title),
                    parentId: nil,
                    level: 0,
                    sortOrder: sortOrder,
                    rawText: rawLine
                )
                items.append(item)
                currentParentId = item.id
                continue
            }

            if let title = parseNumberedLine(line) {
                sortOrder += 1
                let item = WorkItem.create(
                    month: month,
                    title: title,
                    status: .todo,
                    module: ModuleInferer.infer(from: title),
                    parentId: nil,
                    level: 0,
                    sortOrder: sortOrder,
                    rawText: rawLine
                )
                items.append(item)
                currentParentId = item.id
                continue
            }

            if let parsed = parseDashLine(line) {
                sortOrder += 1
                let item = WorkItem.create(
                    month: month,
                    title: parsed.title,
                    status: parsed.isDone ? .done : .todo,
                    module: ModuleInferer.infer(from: parsed.title),
                    parentId: currentParentId,
                    level: currentParentId == nil ? 0 : 1,
                    sortOrder: sortOrder,
                    rawText: rawLine
                )
                items.append(item)
                continue
            }

            sortOrder += 1
            let item = WorkItem.create(
                month: month,
                title: line,
                status: .todo,
                module: ModuleInferer.infer(from: line),
                parentId: nil,
                level: 0,
                sortOrder: sortOrder,
                rawText: rawLine
            )
            items.append(item)
            currentParentId = item.id
        }

        return ParsedWorkLog(month: month, items: items)
    }

    static func export(month: String, items: [WorkItem]) -> String {
        var output: [String] = [month, "---"]

        let parentItems = items
            .filter { $0.parentId == nil }
            .sorted { $0.sortOrder < $1.sortOrder }

        for item in parentItems {
            if let number = item.numberedPrefix {
                output.append("\(number). \(item.title)")
            } else {
                let marker = item.status == .done ? "[x]" : "[ ]"
                output.append("\(marker)\(item.title)")
            }

            let children = items
                .filter { $0.parentId == item.id }
                .sorted { $0.sortOrder < $1.sortOrder }

            for child in children {
                let childMarker = child.status == .done ? "[x]" : "[ ]"
                output.append("   - \(childMarker) \(child.title)")
            }
        }

        return output.joined(separator: "\n")
    }

    private static func detectMonth(from line: String) -> String? {
        DateUtils.isValidMonth(line) ? line : nil
    }

    private static func parseChecklistLine(_ line: String) -> (isDone: Bool, title: String)? {
        let lower = line.lowercased()
        if lower.hasPrefix("[x]") {
            let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : (true, title)
        }
        if lower.hasPrefix("[ ]") {
            let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : (false, title)
        }
        return nil
    }

    private static func parseNumberedLine(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return nil }
        let title = line[line.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func parseDashLine(_ line: String) -> (isDone: Bool, title: String)? {
        guard line.hasPrefix("-") else { return nil }
        var content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        let lower = content.lowercased()

        if lower.hasPrefix("[x]") {
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : (true, content)
        }

        if lower.hasPrefix("[ ]") {
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : (false, content)
        }

        return content.isEmpty ? nil : (false, content)
    }
}
