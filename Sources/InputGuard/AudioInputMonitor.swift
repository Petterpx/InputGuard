import AppKit
import CoreAudio
import Foundation

/// 通过 CoreAudio 的进程对象列表判断语音输入法进程是否正在使用音频输入。
/// 只读系统属性，不申请麦克风权限，不录音。
final class AudioInputMonitor {
    /// true = 正在占用输入；false = 未占用或输入法未运行；nil = CoreAudio 读取失败。
    func isUsingAudioInput(bundleID: String) -> Bool? {
        guard let objectIDs = processObjectIDs() else {
            return nil
        }
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .map { UInt32(bitPattern: $0.processIdentifier) }
        )
        for objectID in objectIDs where belongs(objectID: objectID, to: bundleID, pids: pids) {
            if uint32Property(objectID: objectID, selector: kAudioProcessPropertyIsRunningInput) == 1 {
                return true
            }
        }
        return false
    }

    /// 优先认 CoreAudio 自己报的 bundle ID（输入法进程常不在 `NSRunningApplication` 里），
    /// 读不到时退回 PID 匹配。按前缀认，录音放在辅助进程里的输入法也算。
    private func belongs(objectID: AudioObjectID, to bundleID: String, pids: Set<UInt32>) -> Bool {
        if let processBundleID = stringProperty(objectID: objectID, selector: kAudioProcessPropertyBundleID),
           processBundleID.hasPrefix(bundleID) {
            return true
        }
        guard let pid = uint32Property(objectID: objectID, selector: kAudioProcessPropertyPID) else {
            return false
        }
        return pids.contains(pid)
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
