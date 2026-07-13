import Foundation

enum SQLiteValue {
    case integer(Int64)
    case text(String)
    case null

    var int64Value: Int64? {
        if case let .integer(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        guard let value = int64Value else { return nil }
        return Int(value)
    }

    var stringValue: String? {
        if case let .text(value) = self { return value }
        return nil
    }
}
