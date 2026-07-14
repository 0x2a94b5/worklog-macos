import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarDayChanged),
            name: .NSCalendarDayChanged,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if ProcessInfo.processInfo.environment["WORKLOG_UI_TEST_MODE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.forEach { $0.isReleasedWhenClosed = false }
        AppViewModel.shared.handleCalendarChange()
        DatabaseManager.shared.scheduleDailyBackupIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DatabaseManager.shared.performMaintenance()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    @objc private func workspaceWillSleep() {
        DatabaseManager.shared.performMaintenance()
    }

    @objc private func workspaceDidWake() {
        AppViewModel.shared.handleCalendarChange()
        DatabaseManager.shared.scheduleDailyBackupIfNeeded()
    }

    @objc private func calendarDayChanged() {
        AppViewModel.shared.handleCalendarChange()
        DatabaseManager.shared.scheduleDailyBackupIfNeeded()
    }
}
