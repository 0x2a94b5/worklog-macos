import AppKit
import SwiftUI

struct WorkItemRowView: View {
    private enum EditingField: Hashable {
        case title
        case module
    }

    @EnvironmentObject private var app: AppViewModel
    let item: WorkItem
    var childCount: Int = 0
    var completedChildCount: Int = 0
    var isCollapsed: Bool = false
    var isEditing: Bool = false
    @Binding var editingTitle: String
    @Binding var editingModule: String
    var onToggleCollapse: (() -> Void)?
    var onBeginDrag: (() -> NSItemProvider)?
    var onSelect: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    var onCommitEditing: (() -> Void)?
    var onCancelEditing: (() -> Void)?
    @FocusState private var editingField: EditingField?
    @State private var focusRequestID = UUID().uuidString

    private var isSelected: Bool {
        app.selectedItemId == item.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if item.level > 0 {
                Color.clear
                    .frame(width: CGFloat(item.level * 18), height: 1)
            }

            if let onToggleCollapse {
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(BorderlessButtonStyle())
            } else {
                Color.clear
                    .frame(width: 20, height: 24)
            }

            Button {
                app.toggleDone(item)
            } label: {
                Image(systemName: item.status.symbolName)
                    .foregroundColor(isSelected ? .primary : item.status == .done ? .accentColor : .secondary)
                    .font(.system(size: 17))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(BorderlessButtonStyle())
            .help(item.status == .done ? "标记为未完成" : "标记为已完成")
            .accessibilityLabel(item.status == .done ? "标记为未完成" : "标记为已完成")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let number = item.numberedPrefix {
                        Text("\(number).")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(isSelected ? .primary : .orange)
                    }

                    if isEditing {
                        TextField("任务标题", text: $editingTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: item.level == 0 ? 14 : 13, weight: .regular))
                            .frame(minWidth: 180, maxWidth: .infinity)
                            .layoutPriority(2)
                            .focused($editingField, equals: .title)
                            .background(
                                TextFieldInitialFocus(
                                    requestID: focusRequestID,
                                    caretLocation: (editingTitle as NSString).length
                                )
                            )
                            .submitLabel(.done)
                            .onSubmit { onCommitEditing?() }
                            .onExitCommand { onCancelEditing?() }
                    } else {
                        Text(item.title)
                            .font(.system(size: item.level == 0 ? 14 : 13, weight: .regular))
                            .strikethrough(item.status == .done)
                            .foregroundColor(item.status == .done ? .secondary : .primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(item.title)
                    }

                    if childCount > 0 {
                        Text("\(completedChildCount)/\(childCount)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(isSelected ? Color.primary.opacity(0.10) : Color.secondary.opacity(0.12))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .cornerRadius(5)
                            .help("已完成 \(completedChildCount) / \(childCount) 个子任务")
                    }
                }

                HStack(spacing: 8) {
                    Text(updateMetadataText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("最后更新：\(DateUtils.timestampToDateText(item.updatedAt))")

                    if isEditing {
                        Spacer(minLength: 8)
                        TextField("分类", text: $editingModule)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 140)
                            .focused($editingField, equals: .module)
                            .submitLabel(.done)
                            .onSubmit { onCommitEditing?() }
                            .onExitCommand { onCancelEditing?() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if !isEditing && !item.module.isEmpty {
                Text(item.module)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: moduleTagWidth, alignment: .center)
                    .padding(.vertical, 3)
                    .background(isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.85) : Color.secondary.opacity(0.12))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .cornerRadius(6)
                    .layoutPriority(2)
                    .help(item.module)
            }

            if let onBeginDrag {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onDrag(onBeginDrag)
                    .help("拖动排序")
            }
        }
        .padding(.vertical, item.level == 0 ? 7 : 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title)，\(item.status.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: item.status == .done ? "标记为未完成" : "标记为已完成") {
            app.toggleDone(item)
        }
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded {
                    guard !isEditing else { return }
                    onSelect?()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard !isEditing else { return }
                    DispatchQueue.main.async {
                        guard !isEditing else { return }
                        onBeginEditing?()
                    }
                }
        )
        .onChange(of: isEditing) { editing in
            guard editing else {
                editingField = nil
                return
            }
            focusRequestID = UUID().uuidString
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard isEditing else { return }
                editingField = .title
            }
        }
        .onChange(of: editingField) { field in
            guard isEditing, field == nil else { return }
            DispatchQueue.main.async {
                guard isEditing, editingField == nil else { return }
                onCommitEditing?()
            }
        }
    }

    private var updateMetadataText: String {
        let updatedAt = DateUtils.timestampToCompactDateText(item.updatedAt)
        switch app.selectedScope {
        case .month:
            return "更新于 \(updatedAt)"
        case .module, .status:
            return "\(item.month) · 更新于 \(updatedAt)"
        }
    }

    private var moduleTagWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let textWidth = (item.module as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth) + 16, 32), 96)
    }
}

private struct TextFieldInitialFocus: NSViewRepresentable {
    let requestID: String
    let caretLocation: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.focus(
            from: nsView,
            requestID: requestID,
            caretLocation: caretLocation
        )
    }

    final class Coordinator {
        private var completedRequestID: String?
        private var pendingWorkItem: DispatchWorkItem?
        private var caretCorrectionWorkItem: DispatchWorkItem?

        deinit {
            pendingWorkItem?.cancel()
            caretCorrectionWorkItem?.cancel()
        }

        func focus(from anchorView: NSView, requestID: String, caretLocation: Int) {
            guard completedRequestID != requestID else { return }
            pendingWorkItem?.cancel()
            caretCorrectionWorkItem?.cancel()
            scheduleFocus(
                from: anchorView,
                requestID: requestID,
                caretLocation: caretLocation,
                attemptsRemaining: 5
            )
        }

        private func scheduleFocus(
            from anchorView: NSView,
            requestID: String,
            caretLocation: Int,
            attemptsRemaining: Int
        ) {
            let workItem = DispatchWorkItem { [weak self, weak anchorView] in
                guard let self, let anchorView else { return }
                guard self.completedRequestID != requestID else { return }

                guard let window = anchorView.window,
                      let textField = self.textField(containing: anchorView, in: window),
                      window.makeFirstResponder(textField),
                      let editor = window.fieldEditor(true, for: textField) as? NSTextView else {
                    guard attemptsRemaining > 1 else { return }
                    self.scheduleFocus(
                        from: anchorView,
                        requestID: requestID,
                        caretLocation: caretLocation,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                    return
                }

                let end = min(caretLocation, (editor.string as NSString).length)
                let caretRange = NSRange(location: end, length: 0)
                editor.setSelectedRange(caretRange)
                editor.scrollRangeToVisible(caretRange)
                self.completedRequestID = requestID
                self.scheduleCaretCorrection(
                    editor: editor,
                    requestID: requestID,
                    expectedText: editor.string
                )
            }
            pendingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
        }

        private func scheduleCaretCorrection(
            editor: NSTextView,
            requestID: String,
            expectedText: String
        ) {
            let workItem = DispatchWorkItem { [weak self, weak editor] in
                guard let self,
                      let editor,
                      self.completedRequestID == requestID,
                      editor.string == expectedText else { return }
                let end = (editor.string as NSString).length
                let caretRange = NSRange(location: end, length: 0)
                editor.setSelectedRange(caretRange)
                editor.scrollRangeToVisible(caretRange)
            }
            caretCorrectionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        private func textField(containing anchorView: NSView, in window: NSWindow) -> NSTextField? {
            let anchorCenter = anchorView.convert(
                NSPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY),
                to: nil
            )
            return textFields(in: window.contentView).first { textField in
                !textField.isHidden && textField.convert(textField.bounds, to: nil).contains(anchorCenter)
            }
        }

        private func textFields(in view: NSView?) -> [NSTextField] {
            guard let view else { return [] }
            return view.subviews.flatMap { subview -> [NSTextField] in
                let current = (subview as? NSTextField).map { [$0] } ?? []
                return current + textFields(in: subview)
            }
        }
    }
}
