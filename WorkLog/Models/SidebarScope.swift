import Foundation

enum SidebarScope: Hashable {
    case month(String)
    case module(String)
    case status(WorkItemStatus)
}
