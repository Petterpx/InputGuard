# DoubaoVoiceRestore 设计

日期：2026-09-03

## 背景

豆包输入法 macOS 版（当前 0.9.7）的语音识别好用且免费，但日常输入体验不如其他输入法。
用户把豆包的「全局唤起语音」配成右 Option 按住说话。按下后豆包会自己把系统输入源切成豆包，
语音结束后停在豆包上，不会切回原来的输入法。

已有开源方案（Paxxs/Doubao-ime-hammerspoon 及其 fork、xubihang/Doubao-Voice-Input-Bridge）
都采用「自己监听触发键、切到豆包、模拟豆包的语音快捷键、定时或按键松开后切回」的模型。
这个模型有两个结构性问题：

1. 豆包自己的全局唤起把输入源切走时，脚本不知情，切不回（Paxxs #11）。
2. 依赖模拟豆包的语音快捷键，豆包每改一次默认键就失效（Paxxs #4、PR #5/#6/#7）。

ChaseMoneyChaseFame/doubao-wetype-bridge 采用「纯观察」模型：读 CoreAudio 进程属性判断豆包是否在占用麦克风，
录音结束后切回。但切回目标写死为微信输入法。本项目沿用其检测思路，泛化为「切回切换前的任意输入源」。

## 目标

- 用户按豆包自己的全局语音键说话，说完后自动回到说话前使用的输入源。
- 不合成任何按键，不依赖豆包的快捷键配置，不需要辅助功能与输入监控权限。
- 常驻菜单栏，可暂停、可手动切回、可开机启动。

## 非目标

- 不负责唤起豆包语音，不拦截或转发按键。
- 不支持 Windows。
- 不做自动更新。

## 核心规则

每 50 ms 轮询两个系统状态：当前输入源 ID（Carbon TIS）、豆包进程是否正在占用音频输入
（CoreAudio `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyPID` + `kAudioProcessPropertyIsRunningInput`）。

1. 当前输入源不是豆包（ID 前缀不是 `com.bytedance.inputmethod.doubaoime`），且连续观察 ≥ 0.5 s
   （`sourceSettlePeriod`）时，记为 `lastNonDoubaoSourceID`。豆包唤起语音时输入源会先瞬间跳到 ABC
   键盘布局再进豆包（实测 40~150 ms），稳定期用来排除这个瞬态源。
2. 豆包音频输入从占用变为释放，且此前连续占用 ≥ 0.2 s（`recordingConfirmationPeriod`），进入宽限期。
3. 宽限期（`gracePeriod`，默认 0.6 s）到期时，若当前输入源仍是豆包，切到目标输入源。
   目标解析顺序：用户指定的 `pinnedSourceID`（菜单「切回到」，持久化在 UserDefaults）→
   `lastNonDoubaoSourceID` → 回退源。指定模式下仍持续记录 `lastNonDoubaoSourceID`。
   宽限期内音频再次被占用则取消宽限，回到录音中。宽限期内重入录音不需要再次满足 0.2 s 确认期。
4. 切回后清空录音状态，等待下一次。

## 边界情况

| 情况 | 行为 |
|---|---|
| 手动切到豆包打字、不说话 | 音频从未占用，不切回 |
| 切到豆包数秒后才说话 | 只看音频，仍按规则切回 |
| 启动时已在豆包，无 `lastNonDoubaoSourceID` | 回退到系统启用列表中第一个非豆包输入源 |
| 宽限期内用户手动切走 | 到期时当前源已非豆包，不再操作 |
| 切回失败（目标已禁用等） | 菜单栏显示失败，不重试 |
| 豆包进程未运行 | 音频状态视为未占用 |
| CoreAudio 读取失败 | 菜单栏显示「无法读取录音状态」，不切回 |
| 暂停开关打开 | 只记录 `lastNonDoubaoSourceID`，不切回 |
| 指定的输入源已被禁用或删除 | 退回 `lastNonDoubaoSourceID`，写日志；菜单里仍显示该项并标「已停用」 |

## 组件

### VoiceRestoreCore（库，无系统依赖）

`RestoreStateMachine`：纯值类型状态机。

输入：`observe(sourceID: String, doubaoAudioActive: Bool?, at: Date) -> RestoreAction`
- `sourceID`：当前输入源 ID
- `doubaoAudioActive`：`true` 占用、`false` 释放、`nil` 不可读
- 返回 `RestoreAction`：`.none` / `.restore(to: String)`

展示状态单独暴露为 `public private(set) var status: RestoreStatus`，取值
`waiting` / `recording` / `waitingForCommit` / `audioUnavailable` / `paused` /
`restored(String)` / `restoreFailed(String)`。

内部阶段：`idle` / `recording(since)` / `grace(until)`；切回目标在宽限期到期时
由 `lastNonDoubaoSourceID ?? fallbackSourceID` 解析。

配置：`gracePeriod`、`recordingConfirmationPeriod`、`doubaoPrefix`、`paused`。

`RestoreStateMachine` 只依赖传入的时间，便于测试。

### DoubaoVoiceRestore（App 主目标）

- `InputSourceController`：TIS 读当前源 ID、枚举启用源、按 ID 选择。
- `AudioInputMonitor`：CoreAudio 读豆包进程是否占用输入，移植自 doubao-wetype-bridge（MIT）。
- `RestoreController`：50 ms `Timer`，把两个系统读数喂给状态机，执行 `.restore`，更新状态。
- `StatusMenu`：`NSStatusItem` 菜单。
- `RuntimeLog`：写 `~/Library/Logs/DoubaoVoiceRestore/runtime.log`，不记录文字与语音内容。
- `LaunchAtLogin`：`SMAppService.mainApp`。

### 菜单栏

- 状态行（禁用项）：等待豆包语音 / 豆包语音输入中 / 语音已结束，等待上屏 / 已切回 &lt;名称&gt; / 切回失败 / 无法读取录音状态 / 已暂停
- 立即切回
- 暂停自动切回（勾选）
- 宽限时间：0.4 s / 0.6 s / 1.0 s（单选，持久化到 UserDefaults）
- 开机启动（勾选）
- 打开日志
- 退出

### 打包

- `Package.swift`：macOS 15，targets `VoiceRestoreCore`、`DoubaoVoiceRestore`、`VoiceRestoreCoreTests`。
- `Scripts/build-app.sh`：`swift build -c release`，组装 `build/DoubaoVoiceRestore.app`
  （`Info.plist` 设 `LSUIElement=true`，Bundle ID `dev.petterp.DoubaoVoiceRestore`），ad-hoc 签名。
- README：安装、使用、原理、致谢。

## 测试

单元测试（`swift test`）覆盖状态机：
- 非豆包源连续观察满稳定期才更新 `lastNonDoubaoSourceID`
- 豆包唤起时瞬态跳到 ABC 不会成为切回目标
- 录音 < 0.2 s 释放不触发
- 录音 ≥ 0.2 s 释放，宽限到期且仍在豆包 → `.restore`
- 宽限期内再次占用 → 取消
- 宽限到期时已不在豆包 → 不操作
- 暂停时不触发
- 音频 `nil` 时不触发
- 无 `lastNonDoubaoSourceID` 时用回退源
- 指定 `pinnedSourceID` 时优先于上一个使用的；清空后回到上一个使用的

实机验证（用户机器，macOS 26.3，豆包 0.9.7，Apple 拼音为日常输入源）：
1. 右 Option 说一句，松开后回到 Apple 拼音，文字完整上屏。
2. 连续说两句，中间停顿短于宽限期，不被打断。
3. 手动切到豆包不说话，不被切回。
4. 说话中途切换应用，结束后仍切回。

## 致谢

- CoreAudio 录音状态检测思路来自 ChaseMoneyChaseFame/doubao-wetype-bridge（MIT）。
