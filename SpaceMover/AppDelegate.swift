import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)

            if !SkyLightBridge.isAvailable {
                let alert = NSAlert()
                alert.messageText = "SpaceMover is not compatible with this macOS version"
                alert.informativeText = "Required SkyLight framework symbols are unavailable. This typically happens after a macOS update. Please check for an updated version of SpaceMover."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Quit")
                alert.runModal()
                NSApplication.shared.terminate(nil)
                return
            }

            statusBarController = StatusBarController()
            HotkeyManager.shared.registerHotkeys()

            HotkeyManager.shared.onAction = { [weak self] action in
                self?.statusBarController.handleHotkeyAction(action)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.cleanup()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
