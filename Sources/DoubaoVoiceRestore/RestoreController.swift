import Foundation
import VoiceRestoreCore

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

    init(
        inputSources: InputSourceController = InputSourceController(),
        audioMonitor: AudioInputMonitor = AudioInputMonitor(),
        settings: Settings = .shared
    ) {
        self.inputSources = inputSources
        self.audioMonitor = audioMonitor
        self.settings = settings
        machine = RestoreStateMachine(
            config: RestoreConfig(gracePeriod: settings.gracePeriod),
            fallbackSourceID: inputSources.firstNonDoubaoEnabledID()
        )
        machine.paused = settings.paused
        machine.reset()
    }

    var isPaused: Bool { machine.paused }

    func start() {
        guard timer == nil else { return }
        RuntimeLog.shared.write(
            "started; source=\(inputSources.currentID()); grace=\(settings.gracePeriod); paused=\(machine.paused)"
        )
        publishStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

    func restoreNow() {
        let target = machine.lastNonDoubaoSourceID ?? inputSources.firstNonDoubaoEnabledID()
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
        let audio = audioMonitor.doubaoIsUsingAudioInput()
        logChanges(sourceID: sourceID, audio: audio)

        machine.fallbackSourceID = machine.fallbackSourceID ?? inputSources.firstNonDoubaoEnabledID()
        let action = machine.observe(sourceID: sourceID, doubaoAudioActive: audio, at: Date())
        if case .restore(let target) = action {
            perform(restoreTo: target, reason: "doubao stopped recording")
        }
        publishStatus()
    }

    private func perform(restoreTo target: String, reason: String) {
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
            RuntimeLog.shared.write("doubao audio input; active=\(String(describing: audio))")
            lastLoggedAudio = .some(audio)
        }
    }

    private func publishStatus() {
        let status = machine.status
        guard status != lastStatus else { return }
        lastStatus = status
        statusDidChange?(status, title(for: status))
    }

    private func title(for status: RestoreStatus) -> String {
        switch status {
        case .waiting: return "等待豆包语音"
        case .recording: return "豆包语音输入中"
        case .waitingForCommit: return "语音已结束，等待上屏"
        case .audioUnavailable: return "无法读取豆包录音状态"
        case .paused: return "已暂停自动切回"
        case .restored(let id): return "已切回 \(inputSources.localizedName(for: id))"
        case .restoreFailed(let id): return "切回失败：\(inputSources.localizedName(for: id))"
        }
    }
}
