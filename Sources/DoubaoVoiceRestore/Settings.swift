import Foundation

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private let gracePeriodKey = "gracePeriod"
    private let pausedKey = "paused"

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
}
