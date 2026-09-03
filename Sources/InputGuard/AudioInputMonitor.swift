import AppKit
import CoreAudio
import Foundation

/// 通过 CoreAudio 的进程对象列表判断豆包输入法进程是否正在使用音频输入。
/// 只读系统属性，不申请麦克风权限，不录音。
final class AudioInputMonitor {
    private let doubaoBundleID = "com.bytedance.inputmethod.doubaoime"

    /// true = 正在占用输入；false = 未占用或豆包未运行；nil = CoreAudio 读取失败。
    func doubaoIsUsingAudioInput() -> Bool? {
        guard let objectIDs = processObjectIDs() else {
            return nil
        }
        let doubaoPIDs = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: doubaoBundleID)
                .map { UInt32(bitPattern: $0.processIdentifier) }
        )
        for objectID in objectIDs where isDoubao(objectID: objectID, doubaoPIDs: doubaoPIDs) {
            if uint32Property(objectID: objectID, selector: kAudioProcessPropertyIsRunningInput) == 1 {
                return true
            }
        }
        return false
    }

    /// 优先认 CoreAudio 自己报的 bundle ID（输入法进程常不在 `NSRunningApplication` 里），
    /// 读不到时退回 PID 匹配。
    private func isDoubao(objectID: AudioObjectID, doubaoPIDs: Set<UInt32>) -> Bool {
        if let bundleID = stringProperty(objectID: objectID, selector: kAudioProcessPropertyBundleID),
           bundleID.hasPrefix(doubaoBundleID) {
            return true
        }
        guard let pid = uint32Property(objectID: objectID, selector: kAudioProcessPropertyPID) else {
            return false
        }
        return doubaoPIDs.contains(pid)
    }

    private func processObjectIDs() -> [AudioObjectID]? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }
        var objectIDs = [AudioObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &objectIDs) == noErr else {
            return nil
        }
        return objectIDs
    }

    private func uint32Property(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }
        return value
    }

    private func stringProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr,
              let value
        else {
            return nil
        }
        return value.takeRetainedValue() as String
    }
}
