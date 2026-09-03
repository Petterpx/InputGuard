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

    func testShortBlipDuringGraceStillRestores() {
        var m = makeMachine()
        runRecording(&m, duration: 1.0)                          // 释放 t=1.10，宽限到 1.70
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: true, at: t(1.3)), .none)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.4)), .none, "0.1s 短占释放，重新计宽限到 2.0")
        XCTAssertEqual(m.status, .waitingForCommit)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(1.9)), .none)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(2.05)), .restore(to: pinyin))
    }

    func testResetReflectsPausedFlag() {
        var m = makeMachine()
        runRecording(&m, duration: 1.0)
        m.reset()
        XCTAssertEqual(m.status, .waiting)
        XCTAssertEqual(m.observe(sourceID: doubao, doubaoAudioActive: false, at: t(5)), .none, "reset 后不再切回")
        m.paused = true
        m.reset()
        XCTAssertEqual(m.status, .paused)
    }
}
