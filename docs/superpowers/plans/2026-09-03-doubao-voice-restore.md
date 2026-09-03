# DoubaoVoiceRestore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个 macOS 菜单栏 App：豆包输入法语音录音结束后，自动把系统输入源切回录音前使用的输入源。

**Architecture:** 纯观察模型。一个 50 ms 定时器轮询「当前输入源 ID」和「豆包进程是否占用音频输入」，喂给一个无系统依赖的值类型状态机 `RestoreStateMachine`；状态机在满足条件时返回 `.restore(to:)`，控制器执行 TIS 切换并更新菜单栏状态。不合成按键，不需要任何隐私权限。

**Tech Stack:** Swift 5.10 语言模式（Swift 6.3 工具链），SwiftPM，AppKit（NSStatusItem），Carbon HIToolbox（TIS），CoreAudio（进程属性），ServiceManagement（SMAppService），XCTest。

**Spec:** `docs/superpowers/specs/2026-09-03-doubao-voice-restore-design.md`

## Global Constraints

- 平台：`platforms: [.macOS("15.0")]`；开发机为 macOS 26.3 + Xcode 26.6。
- 语言模式：`swift-tools-version: 5.10`，不开启 Swift 6 严格并发（避免 AppKit 回调的 Sendable 报错）。
- 零第三方依赖。
- 豆包输入源 ID 前缀：`com.bytedance.inputmethod.doubaoime`；豆包进程 Bundle ID：`com.bytedance.inputmethod.doubaoime`。
- Bundle ID：`dev.petterp.DoubaoVoiceRestore`；产品名 `DoubaoVoiceRestore`；菜单栏显示名「豆包回切」。
- 日志路径：`~/Library/Logs/DoubaoVoiceRestore/runtime.log`，不记录任何输入文字或语音内容。
- 不合成任何键盘事件；不申请辅助功能、输入监控、麦克风权限。
- 所有面向用户的文案用中文。
- 每个任务结束时 `swift build` 与 `swift test` 必须通过。
- 提交只 `git add` 本任务涉及的文件，不用 `git add -A`。Commit 信息一行中文，结尾带：
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01XZSx9YCCpsKVJbKGir1T2U
  ```
- 项目根目录：`/Users/petterp/Documents/工具/DoubaoVoiceRestore`。

---

## 文件结构

```
Package.swift
Sources/
  VoiceRestoreCore/
    RestoreStateMachine.swift    # 纯状态机：输入(源ID, 音频状态, 时间) -> 动作；无 import 除 Foundation
  DoubaoVoiceRestore/
    main.swift                   # 入口：--probe 探针模式 / 正常启动 NSApplication
    AppDelegate.swift            # 组装 RestoreController + StatusMenu
    RestoreController.swift      # 50ms 定时器，读系统状态喂状态机，执行切换，发状态回调
    InputSourceController.swift  # Carbon TIS：当前源 ID、枚举启用源、按 ID 选择、ID->显示名
    AudioInputMonitor.swift      # CoreAudio：豆包进程是否占用音频输入
    StatusMenu.swift             # NSStatusItem 菜单
    Settings.swift               # UserDefaults：gracePeriod、paused
    LaunchAtLogin.swift          # SMAppService
    RuntimeLog.swift             # 追加写日志文件
Tests/
  VoiceRestoreCoreTests/
    RestoreStateMachineTests.swift
Resources/
  Info.plist                     # LSUIElement=true
Scripts/
  build-app.sh                   # swift build -c release + 组装 .app + ad-hoc 签名
README.md
docs/superpowers/specs/2026-09-03-doubao-voice-restore-design.md
docs/superpowers/plans/2026-09-03-doubao-voice-restore.md
```

---

### Task 1: Package 骨架 + 状态机（TDD）

**Files:**
- Create: `Package.swift`
- Create: `Sources/VoiceRestoreCore/RestoreStateMachine.swift`
- Create: `Sources/DoubaoVoiceRestore/main.swift`（占位，只 `print`，Task 3 替换）
- Test: `Tests/VoiceRestoreCoreTests/RestoreStateMachineTests.swift`

**Interfaces:**
- Produces（后续任务依赖的精确签名）:
  ```swift
  public struct RestoreConfig: Equatable {
    public var gracePeriod: TimeInterval            // 默认 0.6
    public var recordingConfirmationPeriod: TimeInterval // 默认 0.2
    public var doubaoPrefix: String                 // 默认 "com.bytedance.inputmethod.doubaoime"
    public init(gracePeriod: TimeInterval = 0.6, recordingConfirmationPeriod: TimeInterval = 0.2, doubaoPrefix: String = "com.bytedance.inputmethod.doubaoime")
  }
  public enum RestoreStatus: Equatable {
    case waiting, recording, waitingForCommit, audioUnavailable, paused
    case restored(String), restoreFailed(String)
  }
  public enum RestoreAction: Equatable { case none; case restore(to: String) }
  public struct RestoreStateMachine {
    public var config: RestoreConfig
    public var paused: Bool
    public var fallbackSourceID: String?
    public private(set) var lastNonDoubaoSourceID: String?
    public private(set) var status: RestoreStatus
    public init(config: RestoreConfig = RestoreConfig(), fallbackSourceID: String? = nil)
    public mutating func observe(sourceID: String, doubaoAudioActive: Bool?, at now: Date) -> RestoreAction
    public mutating func didRestore(to sourceID: String, success: Bool)
    public mutating func reset()
  }
  ```

- [ ] **Step 1: 写 Package.swift 和占位 main.swift**

`Package.swift`:
```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DoubaoVoiceRestore",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "DoubaoVoiceRestore", targets: ["DoubaoVoiceRestore"])
    ],
    targets: [
        .target(name: "VoiceRestoreCore", path: "Sources/VoiceRestoreCore"),
        .executableTarget(
            name: "DoubaoVoiceRestore",
            dependencies: ["VoiceRestoreCore"],
            path: "Sources/DoubaoVoiceRestore"
        ),
        .testTarget(
            name: "VoiceRestoreCoreTests",
            dependencies: ["VoiceRestoreCore"],
            path: "Tests/VoiceRestoreCoreTests"
        ),
    ]
)
```

`Sources/DoubaoVoiceRestore/main.swift`（占位）:
```swift
import Foundation
print("DoubaoVoiceRestore placeholder")
```

- [ ] **Step 2: 写失败的测试**

`Tests/VoiceRestoreCoreTests/RestoreStateMachineTests.swift`:
```swift
import XCTest
@testable import VoiceRestoreCore

final class RestoreStateMachineTests: XCTestCase {
    let doubao = "com.bytedance.inputmethod.doubaoime.pinyin"
    let pinyin = "com.apple.inputmethod.SCIM.ITABC"
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func t(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func makeMachine() -> RestoreStateMachine {
        RestoreStateMachine(config: RestoreConfig(gracePeriod: 0.6, recordingConfirmationPeriod: 0.2))
    }

    /// 把一段完整的录音周期喂进去：先在拼音，切到豆包，录 `duration` 秒，释放。
    /// 返回释放那一刻的动作。
    @discardableResult
    func runRecording(_ m: inout RestoreStateMachine, duration: TimeInterval) -> RestoreAction {
        XCTAssertEqual(m.observe(sourceID: pinyin, doubaoAudioActive: false, at: t(0)), .none)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(0.05)), .none)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: true, at: t(0.10)), .none)
        return m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(0.10 + duration))
    }

    func testRemembersLastNonDoubaoSource() {
        var m = makeMachine()
        _ = m.observe(sourceID: pinyin, doubaoAudioActive: false, at: t(0))
        XCTAssertEqual(m.lastNonDoubaoSourceID, pinyin)
        _ = m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(0.05))
        XCTAssertEqual(m.lastNonDoubaoSourceID, pinyin, "切到豆包不应覆盖记录")
        _ = m.observe(sourceID: "com.apple.keylayout.ABC", doubaoAudioActive: false, at: t(0.10))
        XCTAssertEqual(m.lastNonDoubaoSourceID, "com.apple.keylayout.ABC")
    }

    func testShortBlipDoesNotTriggerRestore() {
        var m = makeMachine()
        let action = runRecording(&m, duration: 0.1)   // < 0.2s 确认期
        XCTAssertEqual(action, .none)
        // 宽限期都过了也不切
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(5)), .none)
        XCTAssertEqual(m.status, .waiting)
    }

    func testRestoresAfterGraceWhenStillOnDoubao() {
        var m = makeMachine()
        XCTAssertEqual(runRecording(&m, duration: 1.0), .none)   // 释放时刻 t=1.10
        XCTAssertEqual(m.status, .waitingForCommit)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.5)), .none, "宽限期内不切")
        XCTAssertEqual(
            m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.75)),
            .restore(to: pinyin)
        )
    }

    func testAudioResumedDuringGraceCancelsRestore() {
        var m = makeMachine()
        runRecording(&m, duration: 1.0)                          // 释放 t=1.10
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: true, at: t(1.4)), .none)
        XCTAssertEqual(m.status, .recording)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.8)), .none, "第二段释放，重新计宽限")
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(2.0)), .none)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(2.45)), .restore(to: pinyin))
    }

    func testNoRestoreWhenUserAlreadyLeftDoubao() {
        var m = makeMachine()
        runRecording(&m, duration: 1.0)                          // 释放 t=1.10
        XCTAssertEqual(m.observe(sourceID: pinyin, doubaoAudioActive: false, at: t(1.8)), .none)
        XCTAssertEqual(m.status, .waiting)
    }

    func testPausedNeverRestores() {
        var m = makeMachine()
        m.paused = true
        runRecording(&m, duration: 1.0)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(5)), .none)
        XCTAssertEqual(m.status, .paused)
        XCTAssertEqual(m.lastNonDoubaoSourceID, pinyin, "暂停时仍要记录非豆包源")
    }

    func testNilAudioNeverRestores() {
        var m = makeMachine()
        _ = m.observe(sourceID: pinyin, doubaoAudioActive: nil, at: t(0))
        _ = m.observe(sourceID: doubao, doubaoAudioActive: nil, at: t(0.1))
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: nil, at: t(5)), .none)
        XCTAssertEqual(m.status, .audioUnavailable)
    }

    func testUsesFallbackWhenNothingRemembered() {
        var m = RestoreStateMachine(
            config: RestoreConfig(gracePeriod: 0.6, recordingConfirmationPeriod: 0.2),
            fallbackSourceID: "com.apple.keylayout.ABC"
        )
        _ = m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(0))
        _ = m.observe(sourceID: doubao, doubaoAudioActive: true, at: t(0.1))
        _ = m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.1))
        XCTAssertEqual(
            m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.75)),
            .restore(to: "com.apple.keylayout.ABC")
        )
    }

    func testNoTargetAtAllReportsFailure() {
        var m = makeMachine()
        _ = m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(0))
        _ = m.observe(sourceID: doubao, doubaoAudioActive: true, at: t(0.1))
        _ = m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.1))
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.75)), .none)
        XCTAssertEqual(m.status, .restoreFailed("没有可切回的输入源"))
    }

    func testDidRestoreUpdatesStatus() {
        var m = makeMachine()
        m.didRestore(to: pinyin, success: true)
        XCTAssertEqual(m.status, .restored(pinyin))
        m.didRestore(to: pinyin, success: false)
        XCTAssertEqual(m.status, .restoreFailed(pinyin))
    }

    func testRestoreOnlyFiresOnce() {
        var m = makeMachine()
        runRecording(&m, duration: 1.0)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.75)), .restore(to: pinyin))
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.80)), .none, "同一周期不重复触发")
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore" && swift test 2>&1 | tail -20`
Expected: 编译错误，`RestoreStateMachine` 未定义。

- [ ] **Step 4: 实现状态机**

`Sources/VoiceRestoreCore/RestoreStateMachine.swift`:
```swift
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
                phase = .recording(since: now)
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
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore" && swift test 2>&1 | tail -20`
Expected: `Executed 11 tests, with 0 failures`。

- [ ] **Step 6: 提交**

```bash
cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore"
git add Package.swift Sources/VoiceRestoreCore/RestoreStateMachine.swift Sources/DoubaoVoiceRestore/main.swift Tests/VoiceRestoreCoreTests/RestoreStateMachineTests.swift
git commit -m "feat: 状态机与 Package 骨架

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XZSx9YCCpsKVJbKGir1T2U"
```

---

### Task 2: 系统适配层 + 探针模式

**Files:**
- Create: `Sources/DoubaoVoiceRestore/InputSourceController.swift`
- Create: `Sources/DoubaoVoiceRestore/AudioInputMonitor.swift`
- Create: `Sources/DoubaoVoiceRestore/RuntimeLog.swift`
- Modify: `Sources/DoubaoVoiceRestore/main.swift`（加 `--probe` 模式）

**Interfaces:**
- Produces:
  ```swift
  struct InputSourceInfo: Equatable { let id: String; let name: String }
  final class InputSourceController {
    static let doubaoPrefix = "com.bytedance.inputmethod.doubaoime"
    func currentID() -> String                      // 读不到返回 "unknown"
    func enabledSources() -> [InputSourceInfo]      // 仅 kTISPropertyInputSourceIsEnabled==true 且可选择的键盘类输入源
    func localizedName(for id: String) -> String    // 找不到返回 id 本身
    func firstNonDoubaoEnabledID() -> String?
    @discardableResult func select(id: String) -> Bool
  }
  final class AudioInputMonitor {
    func doubaoIsUsingAudioInput() -> Bool?         // nil = 读取失败；豆包未运行 = false
  }
  final class RuntimeLog {
    static let shared: RuntimeLog
    let fileURL: URL                                // ~/Library/Logs/DoubaoVoiceRestore/runtime.log
    func write(_ message: String)                   // 追加 "yyyy-MM-dd HH:mm:ss.SSS message\n"
  }
  ```

系统 API 没法单元测试，本任务的验证手段是 `--probe`：进程每 100 ms 打印一行当前输入源 ID 与豆包音频状态，跑 8 秒退出。

- [ ] **Step 1: 写 InputSourceController**

```swift
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
```

- [ ] **Step 2: 写 AudioInputMonitor**

```swift
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
        guard !doubaoPIDs.isEmpty else {
            return false
        }
        var sawDoubao = false
        for objectID in objectIDs {
            guard let pid = uint32Property(objectID: objectID, selector: kAudioProcessPropertyPID),
                  doubaoPIDs.contains(pid)
            else {
                continue
            }
            sawDoubao = true
            if uint32Property(objectID: objectID, selector: kAudioProcessPropertyIsRunningInput) == 1 {
                return true
            }
        }
        _ = sawDoubao
        return false
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
}
```

注意：豆包可能有多个进程对象（主进程 + 设置进程）。上面的循环对每个匹配 PID 的对象都检查，任一为 1 即返回 true，而不是像 doubao-wetype-bridge 那样只看第一个。

- [ ] **Step 3: 写 RuntimeLog**

```swift
import Foundation

final class RuntimeLog {
    static let shared = RuntimeLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "dev.petterp.DoubaoVoiceRestore.log")
    private let formatter: DateFormatter

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DoubaoVoiceRestore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("runtime.log")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.fileURL)
            }
        }
    }
}
```

- [ ] **Step 4: main.swift 加 --probe**

替换 `Sources/DoubaoVoiceRestore/main.swift` 为：
```swift
import AppKit
import Foundation

if CommandLine.arguments.contains("--probe") {
    let sources = InputSourceController()
    let audio = AudioInputMonitor()
    print("enabled sources:")
    for s in sources.enabledSources() {
        print("  \(s.id)  [\(s.name)]")
    }
    print("fallback: \(sources.firstNonDoubaoEnabledID() ?? "nil")")
    print("probing for 8s (100ms)...")
    let end = Date().addingTimeInterval(8)
    var last = ""
    while Date() < end {
        let line = "source=\(sources.currentID())  doubaoAudio=\(String(describing: audio.doubaoIsUsingAudioInput()))"
        if line != last {
            print(line)
            last = line
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    exit(0)
}

print("DoubaoVoiceRestore placeholder; use --probe")
```

- [ ] **Step 5: 编译并跑探针**

Run: `cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore" && swift build 2>&1 | tail -5 && swift run DoubaoVoiceRestore --probe`
Expected: 列出启用输入源（含 `com.apple.inputmethod.SCIM.ITABC`），fallback 非 nil，随后打印 `source=... doubaoAudio=Optional(false)`。`doubaoAudio` 不能是 `nil`。若是 `nil`，CoreAudio 调用失败，需要在 `AudioInputMonitor` 打印 `AudioObjectGetPropertyData` 的返回码排查。

如果豆包不在启用列表里（前期排查发现 `AppleEnabledInputSources` 只有 Apple 拼音和 ABC），探针里 `enabledSources()` 不会出现豆包，这不影响本任务，但要在最终报告里向用户指出。

- [ ] **Step 6: swift test 仍通过，提交**

```bash
cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore"
swift test 2>&1 | tail -3
git add Sources/DoubaoVoiceRestore/InputSourceController.swift Sources/DoubaoVoiceRestore/AudioInputMonitor.swift Sources/DoubaoVoiceRestore/RuntimeLog.swift Sources/DoubaoVoiceRestore/main.swift
git commit -m "feat: 输入源与音频状态适配层，加探针模式

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XZSx9YCCpsKVJbKGir1T2U"
```

---

### Task 3: 控制器 + 菜单栏 App

**Files:**
- Create: `Sources/DoubaoVoiceRestore/Settings.swift`
- Create: `Sources/DoubaoVoiceRestore/LaunchAtLogin.swift`
- Create: `Sources/DoubaoVoiceRestore/RestoreController.swift`
- Create: `Sources/DoubaoVoiceRestore/StatusMenu.swift`
- Create: `Sources/DoubaoVoiceRestore/AppDelegate.swift`
- Modify: `Sources/DoubaoVoiceRestore/main.swift`

**Interfaces:**
- Consumes: Task 1 的 `RestoreStateMachine` / `RestoreConfig` / `RestoreStatus` / `RestoreAction`；Task 2 的 `InputSourceController` / `AudioInputMonitor` / `RuntimeLog`。
- Produces:
  ```swift
  final class Settings {
    static let shared: Settings
    var gracePeriod: TimeInterval { get set }   // UserDefaults "gracePeriod"，默认 0.6
    var paused: Bool { get set }                // UserDefaults "paused"，默认 false
  }
  enum LaunchAtLogin { static var isEnabled: Bool { get }; static func set(_ enabled: Bool) throws }
  final class RestoreController {
    var statusDidChange: ((RestoreStatus, String) -> Void)?  // (状态, 供显示的中文文案)
    var isPaused: Bool { get }
    func start(); func stop()
    func setPaused(_ paused: Bool)
    func setGracePeriod(_ seconds: TimeInterval)
    func restoreNow()
  }
  final class StatusMenu: NSObject { init(controller: RestoreController) }
  ```

- [ ] **Step 1: Settings.swift**

```swift
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
```

- [ ] **Step 2: LaunchAtLogin.swift**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

注意：`SMAppService.mainApp` 只有在以 `.app` 包形式运行时才有效；`swift run` 直接跑二进制时 `register()` 会抛错，菜单里要把错误写日志并弹一次 `NSAlert`，不能崩溃。

- [ ] **Step 3: RestoreController.swift**

```swift
import Foundation
import VoiceRestoreCore

final class RestoreController {
    var statusDidChange: ((RestoreStatus, String) -> Void)?

    private let inputSources: InputSourceController
    private let audioMonitor: AudioInputMonitor
    private let settings: Settings
    private var machine: RestoreStateMachine
    private var timer: Timer?
    private var lastLoggedSourceID = ""
    private var lastLoggedAudio: Bool??
    private var lastStatus: RestoreStatus?

    init(
        inputSources: InputSourceController = InputSourceController(),
        audioMonitor: AudioInputMonitor = AudioInputMonitor(),
        settings: Settings = .shared
    ) {
        self.inputSources = inputSources
        self.audioMonitor = audioMonitor
        self.settings = settings
        machine = RestoreStateMachine(
            config: RestoreConfig(gracePeriod: settings.gracePeriod),
            fallbackSourceID: inputSources.firstNonDoubaoEnabledID()
        )
        machine.paused = settings.paused
    }

    var isPaused: Bool { machine.paused }

    func start() {
        guard timer == nil else { return }
        RuntimeLog.shared.write("started; source=\(inputSources.currentID()); grace=\(settings.gracePeriod); paused=\(machine.paused)")
        publishStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setPaused(_ paused: Bool) {
        machine.paused = paused
        settings.paused = paused
        machine.reset()
        RuntimeLog.shared.write("paused=\(paused)")
        publishStatus()
    }

    func setGracePeriod(_ seconds: TimeInterval) {
        machine.config.gracePeriod = seconds
        settings.gracePeriod = seconds
        RuntimeLog.shared.write("gracePeriod=\(seconds)")
    }

    func restoreNow() {
        let target = machine.lastNonDoubaoSourceID ?? inputSources.firstNonDoubaoEnabledID()
        guard let target else {
            machine.didRestore(to: "没有可切回的输入源", success: false)
            publishStatus()
            return
        }
        perform(restoreTo: target, reason: "manual")
    }

    // MARK: - Private

    private func poll() {
        let sourceID = inputSources.currentID()
        let audio = audioMonitor.doubaoIsUsingAudioInput()
        logChanges(sourceID: sourceID, audio: audio)

        machine.fallbackSourceID = machine.fallbackSourceID ?? inputSources.firstNonDoubaoEnabledID()
        let action = machine.observe(sourceID: sourceID, doubaoAudioActive: audio, at: Date())
        if case .restore(let target) = action {
            perform(restoreTo: target, reason: "doubao stopped recording")
        }
        publishStatus()
    }

    private func perform(restoreTo target: String, reason: String) {
        let ok = inputSources.select(id: target)
        machine.didRestore(to: target, success: ok)
        RuntimeLog.shared.write("restore \(ok ? "ok" : "failed"); target=\(target); reason=\(reason)")
        publishStatus()
    }

    private func logChanges(sourceID: String, audio: Bool?) {
        if sourceID != lastLoggedSourceID {
            RuntimeLog.shared.write("source changed; from=\(lastLoggedSourceID); to=\(sourceID)")
            lastLoggedSourceID = sourceID
        }
        if lastLoggedAudio == nil || lastLoggedAudio! != audio {
            RuntimeLog.shared.write("doubao audio input; active=\(String(describing: audio))")
            lastLoggedAudio = .some(audio)
        }
    }

    private func publishStatus() {
        let status = machine.status
        guard status != lastStatus else { return }
        lastStatus = status
        statusDidChange?(status, title(for: status))
    }

    private func title(for status: RestoreStatus) -> String {
        switch status {
        case .waiting: return "等待豆包语音"
        case .recording: return "豆包语音输入中"
        case .waitingForCommit: return "语音已结束，等待上屏"
        case .audioUnavailable: return "无法读取豆包录音状态"
        case .paused: return "已暂停自动切回"
        case .restored(let id): return "已切回 \(inputSources.localizedName(for: id))"
        case .restoreFailed(let id): return "切回失败：\(inputSources.localizedName(for: id))"
        }
    }
}
```

- [ ] **Step 4: StatusMenu.swift**

```swift
import AppKit
import Foundation
import VoiceRestoreCore

final class StatusMenu: NSObject {
    private let controller: RestoreController
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "等待豆包语音", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停自动切回", action: #selector(togglePause), keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var graceItems: [(NSMenuItem, TimeInterval)] = []

    init(controller: RestoreController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "豆"
        statusItem.button?.toolTip = "豆包回切"
        statusItem.menu = buildMenu()
        controller.statusDidChange = { [weak self] status, title in
            DispatchQueue.main.async { self?.apply(status: status, title: title) }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let restoreItem = NSMenuItem(title: "立即切回", action: #selector(restoreNow), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        pauseItem.target = self
        pauseItem.state = controller.isPaused ? .on : .off
        menu.addItem(pauseItem)

        let graceMenu = NSMenu()
        for (label, seconds) in [("0.4 秒", 0.4), ("0.6 秒", 0.6), ("1.0 秒", 1.0)] {
            let item = NSMenuItem(title: label, action: #selector(selectGrace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = abs(Settings.shared.gracePeriod - seconds) < 0.001 ? .on : .off
            graceMenu.addItem(item)
            graceItems.append((item, seconds))
        }
        let graceParent = NSMenuItem(title: "切回前等待", action: nil, keyEquivalent: "")
        graceParent.submenu = graceMenu
        menu.addItem(graceParent)
        menu.addItem(.separator())

        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let logItem = NSMenuItem(title: "打开日志", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func apply(status: RestoreStatus, title: String) {
        statusLine.title = title
        switch status {
        case .recording: statusItem.button?.title = "🎙"
        case .waitingForCommit: statusItem.button?.title = "…"
        case .paused: statusItem.button?.title = "豆⏸"
        case .audioUnavailable, .restoreFailed: statusItem.button?.title = "豆!"
        default: statusItem.button?.title = "豆"
        }
    }

    @objc private func restoreNow() { controller.restoreNow() }

    @objc private func togglePause() {
        let paused = !controller.isPaused
        controller.setPaused(paused)
        pauseItem.state = paused ? .on : .off
    }

    @objc private func selectGrace(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        controller.setGracePeriod(seconds)
        for (item, value) in graceItems {
            item.state = abs(value - seconds) < 0.001 ? .on : .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.set(enable)
            launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        } catch {
            RuntimeLog.shared.write("launch at login failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "设置开机启动失败"
            alert.informativeText = "请把应用放到「应用程序」文件夹后再试。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(RuntimeLog.shared.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 5: AppDelegate.swift 与 main.swift**

`AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = RestoreController()
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(controller: controller)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        RuntimeLog.shared.write("terminated")
    }
}
```

`main.swift` 把最后一行 `print("DoubaoVoiceRestore placeholder; use --probe")` 替换为：
```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 6: 编译、测试、手动启动看菜单**

Run: `cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore" && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -3`
Expected: 无错误；11 tests 通过。

Run（后台启动 10 秒后杀掉）: `swift run DoubaoVoiceRestore & sleep 10; kill %1; tail -5 ~/Library/Logs/DoubaoVoiceRestore/runtime.log`
Expected: 日志有 `started; source=...` 与 `doubao audio input; active=Optional(false)`，菜单栏出现「豆」。

- [ ] **Step 7: 提交**

```bash
cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore"
git add Sources/DoubaoVoiceRestore/Settings.swift Sources/DoubaoVoiceRestore/LaunchAtLogin.swift Sources/DoubaoVoiceRestore/RestoreController.swift Sources/DoubaoVoiceRestore/StatusMenu.swift Sources/DoubaoVoiceRestore/AppDelegate.swift Sources/DoubaoVoiceRestore/main.swift
git commit -m "feat: 控制器与菜单栏 App

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XZSx9YCCpsKVJbKGir1T2U"
```

---

### Task 4: 打包脚本 + README

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `README.md`

- [ ] **Step 1: Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>DoubaoVoiceRestore</string>
    <key>CFBundleIdentifier</key><string>dev.petterp.DoubaoVoiceRestore</string>
    <key>CFBundleName</key><string>DoubaoVoiceRestore</string>
    <key>CFBundleDisplayName</key><string>豆包回切</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
```

- [ ] **Step 2: build-app.sh**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DoubaoVoiceRestore"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

swift build -c release 2>&1 | tail -3
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier "dev.petterp.DoubaoVoiceRestore" "$APP"
codesign --verify --verbose=2 "$APP"
echo "built: $APP"
```

- [ ] **Step 3: README.md**

```markdown
# 豆包回切 DoubaoVoiceRestore

豆包输入法语音说完后，自动切回你说话前用的输入法。macOS 菜单栏小工具。

## 它解决什么

豆包输入法的「全局唤起语音」按下后会把系统输入法切成豆包，说完停在豆包上不回来。
已有的 Hammerspoon 脚本靠自己监听触发键、模拟豆包的语音快捷键、定时切回，
豆包一改快捷键或用了自己的全局唤起，脚本就失效（见 Paxxs/Doubao-ime-hammerspoon #11、#4、#1）。

本工具不模拟任何按键，只观察两件事：当前输入源是谁、豆包进程有没有在占用麦克风。
豆包录音结束后等一小段时间让文字上屏，再切回录音前的输入源。

## 使用

1. `./Scripts/build-app.sh`，把 `build/DoubaoVoiceRestore.app` 拖到「应用程序」。
2. 打开它，菜单栏出现「豆」。**不需要任何权限**。
3. 在豆包里照常用你的全局语音键（比如右 Option 按住说话）。说完松开，约 0.6 秒后自动回到原输入法。

菜单项：
- 状态行：等待 / 录音中 / 等待上屏 / 已切回 xx / 切回失败
- 立即切回
- 暂停自动切回：临时想用豆包打字时勾上
- 切回前等待：0.4 / 0.6 / 1.0 秒，文字偶尔丢尾巴就调大
- 开机启动
- 打开日志：`~/Library/Logs/DoubaoVoiceRestore/runtime.log`，不含任何输入内容

## 原理

每 50 ms 读一次 Carbon TIS 的当前输入源和 CoreAudio 的进程属性
（`kAudioHardwarePropertyProcessObjectList` → `kAudioProcessPropertyIsRunningInput`）。
状态机在 `Sources/VoiceRestoreCore/RestoreStateMachine.swift`，无系统依赖，`swift test` 可测。

## 致谢

CoreAudio 录音状态检测思路来自 [ChaseMoneyChaseFame/doubao-wetype-bridge](https://github.com/ChaseMoneyChaseFame/doubao-wetype-bridge)（MIT）。

## License

MIT
```

- [ ] **Step 4: 打包并启动**

Run: `cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore" && chmod +x Scripts/build-app.sh && ./Scripts/build-app.sh && open build/DoubaoVoiceRestore.app && sleep 3 && pgrep -fl DoubaoVoiceRestore && tail -3 ~/Library/Logs/DoubaoVoiceRestore/runtime.log`
Expected: `codesign --verify` 无输出（即通过），进程在跑，日志有新的 `started;` 行，菜单栏有「豆」。

- [ ] **Step 5: 提交**

```bash
cd "/Users/petterp/Documents/工具/DoubaoVoiceRestore"
git add Resources/Info.plist Scripts/build-app.sh README.md
git commit -m "chore: 打包脚本与 README

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XZSx9YCCpsKVJbKGir1T2U"
```

---

### Task 5: 实机验证（用户参与）

此任务由主会话执行，不派发子代理。

- [ ] **Step 1: 确认豆包已在系统启用输入源中**

Run: `swift run DoubaoVoiceRestore --probe | head -8`
若列表里没有 `com.bytedance.inputmethod.doubaoime.pinyin`，提示用户到「系统设置 → 键盘 → 输入法」添加豆包，否则豆包自己的全局唤起无法切换。

- [ ] **Step 2: 请用户做四个场景，同时 `tail -f` 日志**

1. 右 Option 说一句，松开后回到 Apple 拼音，文字完整上屏。
2. 连续说两句，中间停顿短于 0.6 秒，不被打断。
3. 手动切到豆包不说话，不被切回。
4. 说话中途切换应用，结束后仍切回。

- [ ] **Step 3: 根据日志调整**

若场景 1 丢字：宽限期改 1.0 秒。若场景 2 被打断：宽限期同样调大。若 `doubao audio input; active=Optional(false)` 从未变 true：豆包可能用了别的进程录音，用 `--probe` 期间说话对照 `NSRunningApplication` 列表排查。

---

## Self-Review

- 规格覆盖：核心规则 → Task 1；边界情况表中的暂停、nil 音频、回退源、失败 → Task 1 测试与 Task 3 控制器；菜单项全部在 Task 3 `StatusMenu`；打包、Info.plist、README、致谢 → Task 4；实机四场景 → Task 5。
- 占位扫描：无 TBD / TODO。
- 类型一致性：`RestoreStatus` 七个 case 在 Task 1、Task 3 `title(for:)`、`StatusMenu.apply` 中一致；`observe(sourceID:doubaoAudioActive:at:)` 签名在测试、状态机、控制器中一致；`firstNonDoubaoEnabledID()` 在 Task 2 定义、Task 3 使用。
