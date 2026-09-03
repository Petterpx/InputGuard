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
非豆包输入源要连续待满 0.5 秒才被记为切回目标：豆包唤起语音时输入源会先瞬间跳到 ABC 再进豆包，
不过滤的话说完会被切到 ABC 而不是你原来的输入法。
状态机在 `Sources/VoiceRestoreCore/RestoreStateMachine.swift`，无系统依赖，`swift test` 可测。

## 致谢

CoreAudio 录音状态检测思路来自 [ChaseMoneyChaseFame/doubao-wetype-bridge](https://github.com/ChaseMoneyChaseFame/doubao-wetype-bridge)（MIT）。

## License

MIT
