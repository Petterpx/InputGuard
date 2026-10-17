import Foundation

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private let gracePeriodKey = "gracePeriod"
    private let pausedKey = "paused"
    private let pinnedSourceIDKey = "pinnedSourceID"
    private let voiceSourceIDKey = "voiceSourceID"

    var gracePeriod: TimeInterval {
        get {
            let value = defaults.double(forKey: gracePeriodKey)
            return value > 0 ? value : 0.6
        }
        set { defaults.set(newValue, forKey: gracePeriodKey) }
    }

    var paused: Bool {
        get { defaults.bool(forKey: pausedKey) }
        set { defaults.set(newValue, forKey: pausedKey) }
    }

    /// 固定切回的输入源 ID；nil 表示切回上一个使用的。
    var pinnedSourceID: String? {
        get {
            let value = defaults.string(forKey: pinnedSourceIDKey)
            return value?.isEmpty == false ? value : nil
        }
        set { defaults.set(newValue, forKey: pinnedSourceIDKey) }
    }

    /// 语音输入法的 bundle ID；没设置过时是豆包。
    var voiceSourceID: String {
        get {
            let value = defaults.string(forKey: voiceSourceIDKey)
            return value?.isEmpty == false ? value! : InputSourceController.doubaoBundleID
        }
        set { defaults.set(newValue, forKey: voiceSourceIDKey) }
    }
}
