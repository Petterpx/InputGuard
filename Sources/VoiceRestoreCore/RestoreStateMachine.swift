import Foundation

public struct RestoreConfig: Equatable {
    public var gracePeriod: TimeInterval
    public var recordingConfirmationPeriod: TimeInterval
    /// 非豆包输入源要连续观察到这么久才记为切回目标。
    /// 豆包唤起语音时输入源会先瞬间跳到 ABC 键盘布局再进豆包（实测 40~150 ms），
    /// 不设稳定期的话这个瞬态 ABC 会被当成用户之前的输入法。
    public var sourceSettlePeriod: TimeInterval
    public var doubaoPrefix: String

    public init(
        gracePeriod: TimeInterval = 0.6,
        recordingConfirmationPeriod: TimeInterval = 0.2,
        sourceSettlePeriod: TimeInterval = 0.5,
        doubaoPrefix: String = "com.bytedance.inputmethod.doubaoime"
    ) {
        self.gracePeriod = gracePeriod
        self.recordingConfirmationPeriod = recordingConfirmationPeriod
        self.sourceSettlePeriod = sourceSettlePeriod
        self.doubaoPrefix = doubaoPrefix
    }
}

public enum RestoreStatus: Equatable {
    case waiting
    case recording
    case waitingForCommit
    case audioUnavailable
    case paused
    case restored(String)
    case restoreFailed(String)
}

public enum RestoreAction: Equatable {
    case none
    case restore(to: String)
}

/// 纯状态机。输入：当前输入源 ID、豆包是否占用音频输入、当前时间。
/// 输出：是否需要切回、切回哪里。不依赖任何系统 API。
public struct RestoreStateMachine {
    public var config: RestoreConfig
    public var paused: Bool = false
    public var fallbackSourceID: String?
    public private(set) var lastNonDoubaoSourceID: String?
    public private(set) var status: RestoreStatus = .waiting

    private enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case grace(until: Date)
    }

    private var phase: Phase = .idle
    /// 正在等待稳定期的非豆包源：从什么时候开始连续看到它。
    private var settlingSource: (id: String, since: Date)?

    public init(config: RestoreConfig = RestoreConfig(), fallbackSourceID: String? = nil) {
        self.config = config
        self.fallbackSourceID = fallbackSourceID
    }

    public mutating func reset() {
        phase = .idle
        status = paused ? .paused : .waiting
    }

    public mutating func didRestore(to sourceID: String, success: Bool) {
        status = success ? .restored(sourceID) : .restoreFailed(sourceID)
    }

    private mutating func trackNonDoubaoSource(_ sourceID: String, isDoubao: Bool, at now: Date) {
        guard !isDoubao, sourceID != lastNonDoubaoSourceID else {
            settlingSource = nil
            return
        }
        guard let settling = settlingSource, settling.id == sourceID else {
            settlingSource = (sourceID, now)
            return
        }
        if now.timeIntervalSince(settling.since) >= config.sourceSettlePeriod {
            lastNonDoubaoSourceID = sourceID
            settlingSource = nil
        }
    }

    public mutating func observe(sourceID: String, doubaoAudioActive: Bool?, at now: Date) -> RestoreAction {
        let isDoubao = sourceID.hasPrefix(config.doubaoPrefix)
        trackNonDoubaoSource(sourceID, isDoubao: isDoubao, at: now)

        if paused {
            phase = .idle
            status = .paused
            return .none
        }

        guard let audioActive = doubaoAudioActive else {
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
                // 宽限期内重入录音：豆包为完成识别短暂重开输入单元，
                // 这次重入不需要再次满足确认期，否则短促的重入会把整轮切回吞掉。
                phase = .recording(since: now.addingTimeInterval(-config.recordingConfirmationPeriod))
                status = .recording
                return .none
            }
            guard now >= until else {
                return .none
            }
            phase = .idle
            guard isDoubao else {
                status = .waiting
                return .none
            }
            guard let target = lastNonDoubaoSourceID ?? fallbackSourceID else {
                status = .restoreFailed("没有可切回的输入源")
                return .none
            }
            return .restore(to: target)
        }
    }
}
