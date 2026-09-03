import Foundation

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private let gracePeriodKey = "gracePeriod"
    private let pausedKey = "paused"
    private let pinnedSourceIDKey = "pinnedSourceID"

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
}
