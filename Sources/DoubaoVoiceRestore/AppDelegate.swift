import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = RestoreController()
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(controller: controller)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        RuntimeLog.shared.write("terminated")
        RuntimeLog.shared.flush()
    }
}
