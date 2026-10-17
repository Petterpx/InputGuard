import Foundation

public struct RestoreConfig: Equatable {
    public var gracePeriod: TimeInterval
    public var recordingConfirmationPeriod: TimeInterval
    /// 非语音输入源要连续观察到这么久才记为切回目标。
    /// 豆包唤起语音时输入源会先瞬间跳到 ABC 键盘布局再进豆包（实测 40~150 ms），
    /// 不设稳定期的话这个瞬态 ABC 会被当成用户之前的输入法。
    public var sourceSettlePeriod: TimeInterval
    /// 语音输入法的 bundle ID，例如豆包是 `com.bytedance.inputmethod.doubaoime`。
    /// 它的各个输入模式 ID 都以「bundle ID + .」开头。
    public var voiceSourceID: String

    public init(
        gracePeriod: TimeInterval = 0.6,
        recordingConfirmationPeriod: TimeInterval = 0.2,
        sourceSettlePeriod: TimeInterval = 0.5,
        voiceSourceID: String = "com.bytedance.inputmethod.doubaoime"
    ) {
        self.gracePeriod = gracePeriod
        self.recordingConfirmationPeriod = recordingConfirmationPeriod
        self.sourceSettlePeriod = sourceSettlePeriod
        self.voiceSourceID = voiceSourceID
    }

    public func isVoiceSource(_ sourceID: String) -> Bool {
        sourceID == voiceSourceID || sourceID.hasPrefix(voiceSourceID + ".")
    }
}

public enum RestoreStatus: Equatable {
    case waiting
    case recording
    case waitingForCommit
    case audioUnavailable
    case paused
    /// 选定的语音输入法未安装或已停用。由宿主判断，状态机本身不产生。
    case voiceSourceUnavailable
    case restored(String)
    case restoreFailed(String)
}

public enum RestoreAction: Equatable {
    case none
    case restore(to: String)
}

/// 纯状态机。输入：当前输入源 ID、语音输入法是否占用音频输入、当前时间。
/// 输出：是否需要切回、切回哪里。不依赖任何系统 API。
public struct RestoreStateMachine {
    public var config: RestoreConfig
    public var paused: Bool = false
    /// 用户指定的固定切回目标。nil 表示切回上一个使用的输入源。
    public var pinnedSourceID: String?
    public var fallbackSourceID: String?
    public private(set) var lastNonVoiceSourceID: String?

    /// 切回目标解析顺序：指定的 → 上一个使用的 → 回退源。
    public var restoreTargetID: String? {
        pinnedSourceID ?? lastNonVoiceSourceID ?? fallbackSourceID
    }
    public private(set) var status: RestoreStatus = .waiting

    private enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case grace(until: Date)
    }

    private var phase: Phase = .idle
    /// 正在等待稳定期的非语音源：从什么时候开始连续看到它。
    private var settlingSource: (id: String, since: Date)?

    public init(config: RestoreConfig = RestoreConfig(), fallbackSourceID: String? = nil) {
        self.config = config
        self.fallbackSourceID = fallbackSourceID
    }

    public mutating func reset() {
        phase = .idle
        status = paused ? .paused : .waiting
    }

    /// 换一个语音输入法。之前记下的切回目标如果正是新的语音输入法，要作废，否则会「切回」到它自己。
    public mutating func setVoiceSourceID(_ id: String) {
        config.voiceSourceID = id
        if let last = lastNonVoiceSourceID, config.isVoiceSource(last) {
            lastNonVoiceSourceID = nil
        }
        settlingSource = nil
        reset()
    }

    public mutating func didRestore(to sourceID: String, success: Bool) {
        status = success ? .restored(sourceID) : .restoreFailed(sourceID)
    }

    private mutating func trackNonVoiceSource(_ sourceID: String, isVoice: Bool, at now: Date) {
        guard !isVoice, sourceID != lastNonVoiceSourceID else {
            settlingSource = nil
            return
        }
        guard let settling = settlingSource, settling.id == sourceID else {
            settlingSource = (sourceID, now)
            return
        }
        if now.timeIntervalSince(settling.since) >= config.sourceSettlePeriod {
            lastNonVoiceSourceID = sourceID
            settlingSource = nil
        }
    }

    public mutating func observe(sourceID: String, voiceAudioActive: Bool?, at now: Date) -> RestoreAction {
        let isVoice = config.isVoiceSource(sourceID)
        trackNonVoiceSource(sourceID, isVoice: isVoice, at: now)

        if paused {
            phase = .idle
            status = .paused
            return .none
        }

        guard let audioActive = voiceAudioActive else {
            phase = .idle
            status = .audioUnavailable
            return .none
        }

        switch phase {
        case .idle:
            if audioActive {
                phase = .recording(since: now)
                status = .recording
            } else if status == .audioUnavailable || status == .paused {
                status = .waiting
            }
            return .none

        case .recording(let since):
            if audioActive {
                return .none
            }
            let confirmed = now.timeIntervalSince(since) >= config.recordingConfirmationPeriod
            if confirmed {
                phase = .grace(until: now.addingTimeInterval(config.gracePeriod))
                status = .waitingForCommit
            } else {
                phase = .idle
                status = .waiting
            }
            return .none

        case .grace(let until):
            if audioActive {
                // 宽限期内重入录音：输入法（实测豆包）为完成识别短暂重开输入单元，
                // 这次重入不需要再次满足确认期，否则短促的重入会把整轮切回吞掉。
                phase = .recording(since: now.addingTimeInterval(-config.recordingConfirmationPeriod))
                status = .recording
                return .none
            }
            guard now >= until else {
                return .none
            }
            phase = .idle
            guard isVoice else {
                status = .waiting
                return .none
            }
            guard let target = restoreTargetID else {
                status = .restoreFailed("没有可切回的输入源")
                return .none
            }
            return .restore(to: target)
        }
    }
}
