import AppKit
import Foundation
import VoiceRestoreCore

final class StatusMenu: NSObject {
    private let controller: RestoreController
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "等待豆包语音", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停自动切回", action: #selector(togglePause), keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var graceItems: [(NSMenuItem, TimeInterval)] = []

    init(controller: RestoreController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "豆"
        statusItem.button?.toolTip = "豆包回切"
        statusItem.menu = buildMenu()
        controller.statusDidChange = { [weak self] status, title in
            DispatchQueue.main.async { self?.apply(status: status, title: title) }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let restoreItem = NSMenuItem(title: "立即切回", action: #selector(restoreNow), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        pauseItem.target = self
        pauseItem.state = controller.isPaused ? .on : .off
        menu.addItem(pauseItem)

        let graceMenu = NSMenu()
        for (label, seconds) in [("0.4 秒", 0.4), ("0.6 秒", 0.6), ("1.0 秒", 1.0)] {
            let item = NSMenuItem(title: label, action: #selector(selectGrace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = abs(Settings.shared.gracePeriod - seconds) < 0.001 ? .on : .off
            graceMenu.addItem(item)
            graceItems.append((item, seconds))
        }
        let graceParent = NSMenuItem(title: "切回前等待", action: nil, keyEquivalent: "")
        graceParent.submenu = graceMenu
        menu.addItem(graceParent)
        menu.addItem(.separator())

        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let logItem = NSMenuItem(title: "打开日志", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func apply(status: RestoreStatus, title: String) {
        statusLine.title = title
        switch status {
        case .recording: statusItem.button?.title = "🎙"
        case .waitingForCommit: statusItem.button?.title = "…"
        case .paused: statusItem.button?.title = "豆⏸"
        case .audioUnavailable, .restoreFailed: statusItem.button?.title = "豆!"
        default: statusItem.button?.title = "豆"
        }
    }

    @objc private func restoreNow() { controller.restoreNow() }

    @objc private func togglePause() {
        let paused = !controller.isPaused
        controller.setPaused(paused)
        pauseItem.state = paused ? .on : .off
    }

    @objc private func selectGrace(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        controller.setGracePeriod(seconds)
        for (item, value) in graceItems {
            item.state = abs(value - seconds) < 0.001 ? .on : .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.set(enable)
            launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        } catch {
            RuntimeLog.shared.write("launch at login failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "设置开机启动失败"
            alert.informativeText = "请把应用放到「应用程序」文件夹后再试。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(RuntimeLog.shared.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
