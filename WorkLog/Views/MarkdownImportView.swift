import SwiftUI

struct MarkdownImportView: View {
    @EnvironmentObject private var app: AppViewModel
    @Environment(\.presentationMode) private var presentationMode

    @State private var markdown = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Markdown 导入")
                .font(.title3)
                .fontWeight(.semibold)

            Text("粘贴月度工作记录，内容会追加到对应月份，不会覆盖已有任务。")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $markdown)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 680, minHeight: 360)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))

            HStack {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
                Spacer()
                Button("追加导入") {
                    if app.importMarkdown(markdown) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(app.previewMarkdownImport(markdown).items.isEmpty)
            }
        }
        .padding(18)
        .onAppear {
            guard markdown.isEmpty else { return }
            markdown = "\(app.selectedMonth)\n---\n"
        }
    }
}
