import SwiftUI

struct DatabaseRecoveryView: View {
    @EnvironmentObject private var app: AppViewModel
    @State private var selectedBackup: DatabaseBackupInfo?
    @State private var showsRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("无法打开工作数据库")
                        .font(.title2.weight(.semibold))
                    Text("任务数据未被修改。请选择一份已有备份进行恢复，或打开数据目录检查文件。")
                        .foregroundColor(.secondary)
                }
            }

            if let failure = app.databaseRecoveryFailure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("可用数据库备份")
                        .font(.headline)
                    Spacer()
                    if app.isScanningDatabaseBackups {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        app.refreshDatabaseBackups()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("重新扫描备份")
                    .disabled(app.isScanningDatabaseBackups || app.isRestoringDatabase)
                }

                if app.databaseBackups.isEmpty && !app.isScanningDatabaseBackups {
                    Text("没有找到可用备份。可以打开数据目录，手动保留数据库文件后再处理。")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(app.databaseBackups, selection: Binding(
                        get: { selectedBackup?.id },
                        set: { selectedID in
                            selectedBackup = app.databaseBackups.first { $0.id == selectedID }
                        }
                    )) { backup in
                        HStack {
                            Image(systemName: "externaldrive")
                                .foregroundColor(.secondary)
                            Text(backup.name)
                                .lineLimit(1)
                            Spacer()
                            Text(Self.dateFormatter.string(from: backup.modifiedAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(backup.id)
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                Button {
                    DatabaseManager.shared.openDataFolder()
                } label: {
                    Label("打开数据目录", systemImage: "folder")
                }

                Spacer()

                Button {
                    showsRestoreConfirmation = true
                } label: {
                    if app.isRestoringDatabase {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("恢复所选备份", systemImage: "arrow.counterclockwise")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBackup == nil || app.isRestoringDatabase)
            }
        }
        .padding(24)
        .confirmationDialog(
            "使用所选备份替换当前数据库？",
            isPresented: $showsRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复数据库", role: .destructive) {
                guard let selectedBackup else { return }
                app.restoreDatabase(from: selectedBackup)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复前会先校验备份，并将当前故障数据库保存在 Backups/Recovery。")
        }
        .onAppear {
            if selectedBackup == nil {
                selectedBackup = app.databaseBackups.first
            }
        }
        .onChange(of: app.databaseBackups) { backups in
            if selectedBackup == nil || !backups.contains(where: { $0.id == selectedBackup?.id }) {
                selectedBackup = backups.first
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
