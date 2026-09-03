import Carbon
import Foundation

struct InputSourceInfo: Equatable {
    let id: String
    let name: String
}

final class InputSourceController {
    static let doubaoPrefix = "com.bytedance.inputmethod.doubaoime"

    func currentID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        return stringProperty(source, kTISPropertyInputSourceID) ?? "unknown"
    }

    func enabledSources() -> [InputSourceInfo] {
        allSources().compactMap { source in
            guard boolProperty(source, kTISPropertyInputSourceIsEnabled),
                  boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  let category = stringProperty(source, kTISPropertyInputSourceCategory),
                  category == (kTISCategoryKeyboardInputSource as String),
                  let id = stringProperty(source, kTISPropertyInputSourceID)
            else {
                return nil
            }
            return InputSourceInfo(id: id, name: stringProperty(source, kTISPropertyLocalizedName) ?? id)
        }
    }

    func localizedName(for id: String) -> String {
        allSources().first { stringProperty($0, kTISPropertyInputSourceID) == id }
            .flatMap { stringProperty($0, kTISPropertyLocalizedName) } ?? id
    }

    func firstNonDoubaoEnabledID() -> String? {
        enabledSources().first { !$0.id.hasPrefix(Self.doubaoPrefix) }?.id
    }

    @discardableResult
    func select(id: String) -> Bool {
        guard let source = allSources().first(where: { stringProperty($0, kTISPropertyInputSourceID) == id }) else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Private

    /// 每次都重新取列表：用户可能随时在系统设置里增删输入源。TIS 调用开销很小。
    private func allSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
