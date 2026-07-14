import SwiftUI

@main
struct WorkLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appViewModel = AppViewModel.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appViewModel)
        }
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("新建工作项") {
                    appViewModel.createEmptyItem()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(appViewModel.requiresDatabaseRecovery)
            }

            CommandMenu("工作项") {
                Button("搜索") {
                    appViewModel.requestSearchFocus()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(appViewModel.requiresDatabaseRecovery)

                Divider()

                Button("导入 Markdown") {
                    appViewModel.showImportSheet = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(appViewModel.requiresDatabaseRecovery)

                Button("导出 Markdown") {
                    appViewModel.exportCurrentMonthToFile()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appViewModel.requiresDatabaseRecovery)

                Button("月度复盘") {
                    appViewModel.showMonthlyReviewSheet = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appViewModel.requiresDatabaseRecovery)

                Divider()

                Button("备份数据库") {
                    appViewModel.createDatabaseBackup()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(appViewModel.requiresDatabaseRecovery)

                Divider()

                Button("删除所选工作项") {
                    appViewModel.requestDeleteSelectedItem()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(appViewModel.requiresDatabaseRecovery || appViewModel.selectedItem == nil)
            }
        }
    }
}
