import Foundation

enum ModuleInferer {
    static func infer(from title: String) -> String {
        let text = title.lowercased()

        if containsAny(text, ["滞纳金", "宽限期"]) { return "滞纳金" }
        if containsAny(text, ["公摊", "分摊", "excel"]) { return "公摊" }
        if containsAny(text, ["小程序", "体验版"]) { return "小程序" }
        if containsAny(text, ["二维码", "支付", "缴费"]) { return "支付" }
        if containsAny(text, ["账单", "欠费", "收费"]) { return "账单" }
        if containsAny(text, ["打印"]) { return "打印" }
        if containsAny(text, ["上线", "恢复"]) { return "发布" }

        return "未分类"
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }
}
