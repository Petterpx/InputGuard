<p align="center">
  <img src="images/app-icon.png" width="128" alt="InputGuard 图标">
</p>

<h1 align="center">InputGuard</h1>

<p align="center">豆包输入法语音说完后，自动切回你说话前用的输入法。</p>

<p align="center">
  <a href="https://github.com/Petterpx/InputGuard/releases/latest"><img src="https://img.shields.io/github/v/release/Petterpx/InputGuard?label=%E4%B8%8B%E8%BD%BD&color=0A5BD6" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Petterpx/InputGuard?color=green" alt="MIT License"></a>
</p>

---

## 解决什么

豆包输入法的「全局唤起语音」会把系统输入法切成豆包，说完就停在豆包上，不会回到你原来用的输入法。

InputGuard 在菜单栏里守着：豆包录音一结束，等文字上屏，自动切回你说话前的输入法。不模拟按键，不需要任何系统权限。

## 安装

1. 到 [Releases](https://github.com/Petterpx/InputGuard/releases/latest) 下载 dmg，打开后把 InputGuard 拖到「应用程序」。
2. 首次打开会被 Gatekeeper 拦下（本地签名，未经 Apple 公证）。右键点击应用选「打开」，或在终端执行：

   ```bash
   xattr -d com.apple.quarantine /Applications/InputGuard.app
   ```

要求 macOS 15 或更新。

## 使用

打开后菜单栏出现键盘图标。在豆包里照常按语音键说话，松开后约 0.6 秒自动回到原输入法。

| 菜单项 | 说明 |
|---|---|
| 立即切回 | 手动切回一次 |
| 暂停自动切回 | 临时想用豆包打字时勾上 |
| 切回前等待 | 0.4 / 0.6 / 1.0 秒，文字偶尔丢尾巴就调大 |
| 切回到 | 默认切回上一个使用的输入法，也可以固定选一个 |
| 开机启动 | 登录时自动运行 |
| 打开日志 | `~/Library/Logs/InputGuard/runtime.log`，不含任何输入内容 |

## License

[MIT](LICENSE)。录音状态检测思路来自 [doubao-wetype-bridge](https://github.com/ChaseMoneyChaseFame/doubao-wetype-bridge)。
