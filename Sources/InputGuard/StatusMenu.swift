import AppKit
import Foundation
import InputGuardCore

final class StatusMenu: NSObject {
    private let controller: RestoreController
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "等待豆包语音", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停自动切回", action: #selector(togglePause), keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var graceItems: [(NSMenuItem, TimeInterval)] = []
    private let targetMenu = NSMenu()

    init(controller: RestoreController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = Self.statusImage(badge: nil)
        statusItem.button?.toolTip = "InputGuard"
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

        // 每次展开时重建：用户可能刚在系统设置里增删了输入法。
        targetMenu.delegate = self
        rebuildTargetMenu()
        let targetParent = NSMenuItem(title: "切回到", action: nil, keyEquivalent: "")
        targetParent.submenu = targetMenu
        menu.addItem(targetParent)
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

    private func rebuildTargetMenu() {
        targetMenu.removeAllItems()
        let pinned = controller.pinnedSourceID

        let lastUsed = NSMenuItem(title: "上一个使用的输入法", action: #selector(selectTarget(_:)), keyEquivalent: "")
        lastUsed.target = self
        lastUsed.state = pinned == nil ? .on : .off
        targetMenu.addItem(lastUsed)
        targetMenu.addItem(.separator())

        var sources = controller.availableRestoreTargets()
        if let pinned, !sources.contains(where: { $0.id == pinned }) {
            // 指定的源已不在启用列表里：仍显示出来并标记，用户能看到为什么没生效。
            sources.append(InputSourceInfo(id: pinned, name: "\(pinned)（已停用）"))
        }
        for source in sources {
            let item = NSMenuItem(title: source.name, action: #selector(selectTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = source.id == pinned ? .on : .off
            targetMenu.addItem(item)
        }
    }

    private func apply(status: RestoreStatus, title: String) {
        statusLine.title = title
        let badge: String?
        switch status {
        case .recording: badge = "mic.fill"
        case .waitingForCommit: badge = "ellipsis"
        case .paused: badge = "pause.fill"
        case .audioUnavailable, .restoreFailed: badge = "exclamationmark"
        default: badge = nil
        }
        statusItem.button?.image = Self.statusImage(badge: badge)
    }

    /// 菜单栏图标：SF Symbol 实心键盘；有状态时按键区被镂空的状态符号替换。
    /// 尺寸与系统 keyboard 符号完全一致，任何状态都不移动、不多占像素。模板图，随浅深色菜单栏反色。
    private static func statusImage(badge: String?) -> NSImage? {
        guard let keyboard = symbol("keyboard.fill", pointSize: 16, weight: .medium) else { return nil }
        let image = NSImage(size: keyboard.size)
        image.lockFocus()
        keyboard.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        if let badge, let glyph = symbol(badge, pointSize: 8.5, weight: .bold) {
            // 盖住按键孔：圆角内矩形，留在键盘轮廓内
            let inset: CGFloat = 2.2
            let inner = NSRect(x: inset, y: inset, width: keyboard.size.width - inset * 2, height: keyboard.size.height - inset * 2)
            NSColor.black.set()
            NSBezierPath(roundedRect: inner, xRadius: 1.2, yRadius: 1.2).fill()
            let origin = NSPoint(x: (keyboard.size.width - glyph.size.width) / 2, y: (keyboard.size.height - glyph.size.height) / 2)
            glyph.draw(at: origin, from: .zero, operation: .destinationOut, fraction: 1)
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "InputGuard"
        return image
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    @objc private func restoreNow() { controller.restoreNow() }

    @objc private func togglePause() {
        let paused = !controller.isPaused
        controller.setPaused(paused)
        pauseItem.state = paused ? .on : .off
    }

    @objc private func selectTarget(_ sender: NSMenuItem) {
        controller.setPinnedSource(sender.representedObject as? String)
        rebuildTargetMenu()
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

extension StatusMenu: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === targetMenu else { return }
        rebuildTargetMenu()
    }
}
