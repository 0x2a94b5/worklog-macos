import Foundation

enum DateUtils {
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let compactDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static func nowTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    static func currentMonth() -> String {
        formatMonth(Date())
    }

    static func formatMonth(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    static func isValidMonth(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil,
              let date = monthFormatter.date(from: value)
        else { return false }
        return monthFormatter.string(from: date) == value
    }

    static func timestampToDateText(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "" }
        return dateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    static func timestampToCompactDateText(_ timestamp: Int64) -> String {
        compactDateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    static func fileSafeTimestamp(_ date: Date = Date()) -> String {
        fileTimestampFormatter.string(from: date)
    }
}
