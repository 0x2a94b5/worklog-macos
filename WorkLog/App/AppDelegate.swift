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
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.forEach { $0.isReleasedWhenClosed = false }
        AppViewModel.shared.handleCalendarChange()
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
    }

    @objc private func calendarDayChanged() {
        AppViewModel.shared.handleCalendarChange()
    }
}
