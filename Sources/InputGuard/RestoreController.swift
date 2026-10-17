import Carbon
import Foundation
import InputGuardCore

final class RestoreController {
    var statusDidChange: ((RestoreStatus, String) -> Void)?

    private let inputSources: InputSourceController
    private let audioMonitor: AudioInputMonitor
    private let settings: Settings
    private var machine: RestoreStateMachine
    private var timer: Timer?
    private var lastLoggedSourceID = ""
    private var lastLoggedAudio: Bool??
    private var lastStatus: RestoreStatus?
    /// 选定的语音输入法当前是否启用。启用列表变化时刷新，不在每次轮询里查。
    private var voiceSourceAvailable = true
    private var enabledSourcesObserver: NSObjectProtocol?

    init(
        inputSources: InputSourceController = InputSourceController(),
        audioMonitor: AudioInputMonitor = AudioInputMonitor(),
        settings: Settings = .shared
    ) {
        self.inputSources = inputSources
        self.audioMonitor = audioMonitor
        self.settings = settings
        machine = RestoreStateMachine(
            config: RestoreConfig(gracePeriod: settings.gracePeriod, voiceSourceID: settings.voiceSourceID)
        )
        machine.fallbackSourceID = firstRestoreTargetID()
        machine.paused = settings.paused
        machine.pinnedSourceID = settings.pinnedSourceID
        machine.reset()
        voiceSourceAvailable = isVoiceSourceEnabled()
    }

    var isPaused: Bool { machine.paused }
    var pinnedSourceID: String? { machine.pinnedSourceID }
    var voiceSourceID: String { machine.config.voiceSourceID }
    var voiceSourceName: String { inputSources.localizedName(for: voiceSourceID) }

    func availableRestoreTargets() -> [InputSourceInfo] {
        inputSources.enabledSources().filter { !machine.config.isVoiceSource($0.id) }
    }

    func availableVoiceSources() -> [InputSourceInfo] {
        inputSources.enabledInputMethods()
    }

    /// 换语音输入法。指定的切回目标如果属于新的语音输入法，一并清掉，否则会切回到它自己。
    func setVoiceSource(_ bundleID: String) {
        machine.setVoiceSourceID(bundleID)
        settings.voiceSourceID = bundleID
        if let pinned = machine.pinnedSourceID, machine.config.isVoiceSource(pinned) {
            setPinnedSource(nil)
        }
        if let fallback = machine.fallbackSourceID, machine.config.isVoiceSource(fallback) {
            machine.fallbackSourceID = nil
        }
        machine.fallbackSourceID = machine.fallbackSourceID ?? firstRestoreTargetID()
        voiceSourceAvailable = isVoiceSourceEnabled()
        RuntimeLog.shared.write("voiceSource=\(bundleID); available=\(voiceSourceAvailable)")
        // 状态可能没变但名字变了（「等待 X 语音」），强制刷新一次。
        lastStatus = nil
        publishStatus()
    }

    func start() {
        guard timer == nil else { return }
        RuntimeLog.shared.write(
            "started; source=\(inputSources.currentID()); voice=\(voiceSourceID); voiceAvailable=\(voiceSourceAvailable); grace=\(settings.gracePeriod); paused=\(machine.paused); pinned=\(machine.pinnedSourceID ?? "none")"
        )
        enabledSourcesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVoiceSourceAvailability()
        }
        publishStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let enabledSourcesObserver {
            DistributedNotificationCenter.default().removeObserver(enabledSourcesObserver)
            self.enabledSourcesObserver = nil
        }
    }

    func refreshVoiceSourceAvailability() {
        let available = isVoiceSourceEnabled()
        guard available != voiceSourceAvailable else { return }
        voiceSourceAvailable = available
        RuntimeLog.shared.write("voiceSource available=\(available); id=\(voiceSourceID)")
        publishStatus()
    }

    func setPaused(_ paused: Bool) {
        machine.paused = paused
        settings.paused = paused
        machine.reset()
        RuntimeLog.shared.write("paused=\(paused)")
        publishStatus()
    }

    func setGracePeriod(_ seconds: TimeInterval) {
        machine.config.gracePeriod = seconds
        settings.gracePeriod = seconds
        RuntimeLog.shared.write("gracePeriod=\(seconds)")
    }

    /// nil = 切回上一个使用的输入源。
    func setPinnedSource(_ id: String?) {
        machine.pinnedSourceID = id
        settings.pinnedSourceID = id
        RuntimeLog.shared.write("pinnedSource=\(id ?? "none")")
    }

    func restoreNow() {
        let target = machine.restoreTargetID ?? firstRestoreTargetID()
        guard let target else {
            machine.didRestore(to: "没有可切回的输入源", success: false)
            publishStatus()
            return
        }
        perform(restoreTo: target, reason: "manual")
    }

    // MARK: - Private

    private func poll() {
        let sourceID = inputSources.currentID()
        let audio = audioMonitor.isUsingAudioInput(bundleID: voiceSourceID)
        logChanges(sourceID: sourceID, audio: audio)

        machine.fallbackSourceID = machine.fallbackSourceID ?? firstRestoreTargetID()
        let action = machine.observe(sourceID: sourceID, voiceAudioActive: audio, at: Date())
        if case .restore(let target) = action {
            perform(restoreTo: target, reason: "voice input stopped recording")
        }
        publishStatus()
    }

    private func perform(restoreTo requested: String, reason: String) {
        var target = requested
        if requested == machine.pinnedSourceID, !inputSources.isEnabled(id: requested) {
            // 指定的输入源已在系统里被禁用或删除：退回上一个使用的，不让切回整个失效。
            let alternative = machine.lastNonVoiceSourceID ?? machine.fallbackSourceID
            RuntimeLog.shared.write("pinned source unavailable; pinned=\(requested); using=\(alternative ?? "none")")
            guard let alternative else {
                machine.didRestore(to: requested, success: false)
                publishStatus()
                return
            }
            target = alternative
        }
        let ok = inputSources.select(id: target)
        machine.didRestore(to: target, success: ok)
        RuntimeLog.shared.write("restore \(ok ? "ok" : "failed"); target=\(target); reason=\(reason)")
        publishStatus()
    }

    private func logChanges(sourceID: String, audio: Bool?) {
        if sourceID != lastLoggedSourceID {
            RuntimeLog.shared.write("source changed; from=\(lastLoggedSourceID); to=\(sourceID)")
            lastLoggedSourceID = sourceID
        }
        if lastLoggedAudio == nil || lastLoggedAudio! != audio {
            RuntimeLog.shared.write("voice audio input; active=\(String(describing: audio))")
            lastLoggedAudio = .some(audio)
        }
    }

    private func firstRestoreTargetID() -> String? {
        availableRestoreTargets().first?.id
    }

    private func isVoiceSourceEnabled() -> Bool {
        availableVoiceSources().contains { $0.id == voiceSourceID }
    }

    private func publishStatus() {
        let status = voiceSourceAvailable ? machine.status : .voiceSourceUnavailable
        guard status != lastStatus else { return }
        lastStatus = status
        statusDidChange?(status, title(for: status))
    }

    private func title(for status: RestoreStatus) -> String {
        switch status {
        case .waiting: return "等待\(voiceSourceName)语音"
        case .recording: return "\(voiceSourceName)语音输入中"
        case .waitingForCommit: return "语音已结束，等待上屏"
        case .audioUnavailable: return "无法读取\(voiceSourceName)录音状态"
        case .paused: return "已暂停自动切回"
        case .voiceSourceUnavailable: return "\(voiceSourceName)未启用，请选择语音输入法"
        case .restored(let id): return "已切回 \(inputSources.localizedName(for: id))"
        case .restoreFailed(let id): return "切回失败：\(inputSources.localizedName(for: id))"
        }
    }
}
