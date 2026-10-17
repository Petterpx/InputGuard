import Carbon
import Foundation

struct InputSourceInfo: Equatable {
    let id: String
    let name: String
}

final class InputSourceController {
    static let doubaoBundleID = "com.bytedance.inputmethod.doubaoime"

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

    /// 已启用的第三方输入法，每个输入法应用一项（不按拼音、五笔等输入模式拆开），`id` 是 bundle ID。
    /// 键盘布局没有自己的进程，不可能占用麦克风；系统自带输入法没有语音输入。两者都不列。
    func enabledInputMethods() -> [InputSourceInfo] {
        let methodTypes: Set<String> = [
            kTISTypeKeyboardInputMethodModeEnabled as String,
            kTISTypeKeyboardInputMethodWithoutModes as String,
        ]
        var seen = Set<String>()
        return allSources().compactMap { source in
            guard boolProperty(source, kTISPropertyInputSourceIsEnabled),
                  let type = stringProperty(source, kTISPropertyInputSourceType), methodTypes.contains(type),
                  let bundleID = stringProperty(source, kTISPropertyBundleID),
                  !bundleID.hasPrefix("com.apple."),
                  seen.insert(bundleID).inserted
            else {
                return nil
            }
            return InputSourceInfo(id: bundleID, name: stringProperty(source, kTISPropertyLocalizedName) ?? bundleID)
        }
    }

    func localizedName(for id: String) -> String {
        allSources(includeAllInstalled: true).first { stringProperty($0, kTISPropertyInputSourceID) == id }
            .flatMap { stringProperty($0, kTISPropertyLocalizedName) } ?? (id == Self.doubaoBundleID ? "豆包输入法" : id)
    }

    func isEnabled(id: String) -> Bool {
        enabledSources().contains { $0.id == id }
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
    private func allSources(includeAllInstalled: Bool = false) -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource] else {
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
