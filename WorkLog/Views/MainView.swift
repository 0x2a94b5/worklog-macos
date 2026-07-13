import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        NavigationView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 230)

            WorkListView()
                .frame(minWidth: 420, idealWidth: 540)
        }
        .frame(minWidth: 680, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("显示或隐藏侧边栏")
            }

            ToolbarItemGroup {
                Button {
                    app.createEmptyItem()
                } label: {
                    Label("新增工作项", systemImage: "plus")
                }

                Button {
                    app.showImportSheet = true
                } label: {
                    Label("导入 Markdown", systemImage: "square.and.arrow.down")
                }

                Button {
                    app.exportCurrentMonthToFile()
                } label: {
                    Label("导出 Markdown", systemImage: "square.and.arrow.up")
                }

                Button {
                    app.showMonthlyReviewSheet = true
                } label: {
                    Label("月度复盘", systemImage: "chart.pie")
                }
            }
        }
        .sheet(isPresented: $app.showImportSheet) {
            MarkdownImportView()
                .environmentObject(app)
        }
        .sheet(isPresented: $app.showMonthlyReviewSheet) {
            MonthlyReviewView()
                .environmentObject(app)
        }
        .alert(item: Binding(
            get: { app.errorMessage.map { AlertMessage(message: $0) } },
            set: { _ in app.errorMessage = nil }
        )) { alert in
            Alert(title: Text("操作失败"), message: Text(alert.message), dismissButton: .default(Text("知道了")))
        }
    }
}

private struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}
