import AppKit
import Foundation
import InputGuardCore

final class StatusMenu: NSObject {
    private let controller: RestoreController
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停自动切回", action: #selector(togglePause), keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var graceItems: [(NSMenuItem, TimeInterval)] = []
    private let customGraceItem = NSMenuItem(title: "自定义…", action: #selector(selectCustomGrace), keyEquivalent: "")
    private let targetMenu = NSMenu()
    private let voiceMenu = NSMenu()

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

        // 每次展开时重建，理由同「切回到」。
        voiceMenu.delegate = self
        rebuildVoiceMenu()
        let voiceParent = NSMenuItem(title: "语音输入法", action: nil, keyEquivalent: "")
        voiceParent.submenu = voiceMenu
        menu.addItem(voiceParent)

        let graceMenu = NSMenu()
        for seconds in [0.4, 0.6, 1.0, 3.0, 5.0] {
            let item = NSMenuItem(title: "\(Self.formatSeconds(seconds)) 秒", action: #selector(selectGrace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            graceMenu.addItem(item)
            graceItems.append((item, seconds))
        }
        graceMenu.addItem(.separator())
        customGraceItem.target = self
        graceMenu.addItem(customGraceItem)
        refreshGraceMenu()
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

    private func rebuildVoiceMenu() {
        voiceMenu.removeAllItems()
        let current = controller.voiceSourceID
        var methods = controller.availableVoiceSources()
        if !methods.contains(where: { $0.id == current }) {
            methods.append(InputSourceInfo(id: current, name: "\(controller.voiceSourceName)（未启用）"))
        }
        for method in methods {
            let item = NSMenuItem(title: method.name, action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = method.id
            item.state = method.id == current ? .on : .off
            voiceMenu.addItem(item)
        }
        voiceMenu.addItem(.separator())
        let hint = NSMenuItem(title: "只列已启用的输入法，没看到就先去系统设置添加", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        voiceMenu.addItem(hint)
    }

    private func apply(status: RestoreStatus, title: String) {
        statusLine.title = title
        let badge: String?
        switch status {
        case .recording: badge = "mic.fill"
        case .waitingForCommit: badge = "ellipsis"
        case .paused: badge = "pause.fill"
        case .audioUnavailable, .restoreFailed, .voiceSourceUnavailable: badge = "exclamationmark"
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

    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.setVoiceSource(id)
        rebuildVoiceMenu()
    }

    @objc private func selectGrace(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        controller.setGracePeriod(seconds)
        refreshGraceMenu()
    }

    @objc private func selectCustomGrace() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = Self.formatSeconds(Settings.shared.gracePeriod)
        field.placeholderString = "例如 2.5"

        let alert = NSAlert()
        alert.messageText = "自定义切回前等待"
        alert.informativeText = "输入 \(Self.formatSeconds(Self.customGraceRange.lowerBound))～\(Self.formatSeconds(Self.customGraceRange.upperBound)) 之间的秒数。"
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        // 菜单栏应用没有前台窗口，不激活的话弹窗拿不到键盘焦点。
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "。", with: ".")
        guard let seconds = Double(text), Self.customGraceRange.contains(seconds) else {
            let error = NSAlert()
            error.messageText = "无效的等待时间"
            error.informativeText = "请输入 \(Self.formatSeconds(Self.customGraceRange.lowerBound))～\(Self.formatSeconds(Self.customGraceRange.upperBound)) 之间的数字。"
            error.runModal()
            return
        }
        controller.setGracePeriod(seconds)
        refreshGraceMenu()
    }

    private static let customGraceRange: ClosedRange<TimeInterval> = 0.1...30

    /// 勾选当前值；不在预设里时勾「自定义」并把数值写进标题。
    private func refreshGraceMenu() {
        let current = Settings.shared.gracePeriod
        var matched = false
        for (item, value) in graceItems {
            let isOn = abs(value - current) < 0.001
            item.state = isOn ? .on : .off
            matched = matched || isOn
        }
        customGraceItem.state = matched ? .off : .on
        customGraceItem.title = matched ? "自定义…" : "自定义（\(Self.formatSeconds(current)) 秒）…"
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: seconds)) ?? "\(seconds)"
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
        if menu === targetMenu {
            rebuildTargetMenu()
        } else if menu === voiceMenu {
            controller.refreshVoiceSourceAvailability()
            rebuildVoiceMenu()
        }
    }
}
