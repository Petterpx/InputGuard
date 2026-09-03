import Foundation

public struct RestoreConfig: Equatable {
    public var gracePeriod: TimeInterval
    public var recordingConfirmationPeriod: TimeInterval
    public var doubaoPrefix: String

    public init(
        gracePeriod: TimeInterval = 0.6,
        recordingConfirmationPeriod: TimeInterval = 0.2,
        doubaoPrefix: String = "com.bytedance.inputmethod.doubaoime"
    ) {
        self.gracePeriod = gracePeriod
        self.recordingConfirmationPeriod = recordingConfirmationPeriod
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

    public mutating func observe(sourceID: String, doubaoAudioActive: Bool?, at now: Date) -> RestoreAction {
        let isDoubao = sourceID.hasPrefix(config.doubaoPrefix)
        if !isDoubao {
            lastNonDoubaoSourceID = sourceID
        }

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
