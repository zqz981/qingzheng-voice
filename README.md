# 清正语音

给清正在 Mac 上用的系统级中英语音输入。菜单栏常驻：说话 → 本地转写 → 整理文本 → 插入当前应用光标处。不是拼音输入法。

## 代码在哪（为什么聊天里看不到）

源码在 **git 仓库** 里，不在计划文档里。聊天或 Project 文档只说明产品，真正的 Swift 文件是：

```
QingzhengVoice.xcodeproj          ← 用 Xcode 打开这个
QingzhengVoice/
  QingzhengVoiceApp.swift         ← 入口、菜单栏
  AppModel.swift                  ← 录音/转写/插入流程
  MenuBarView.swift / SettingsView.swift / RecordingHUD.swift
  HotkeyManager.swift             ← Control-Option-空格
  ModernSpeechEngine.swift        ← macOS 26 本地转写
  LegacySpeechEngine.swift        ← 更早系统的转写
  TextPolisher.swift              ← 整理文本
  FocusTarget.swift               ← 钉住当前输入框
  TextInserter.swift              ← 写入焦点控件 / 粘贴
```

分支名：`cursor/qingzheng-voice-input-dd1d`。在 Cursor 左栏切到这个分支，或打开资源管理器里的 `QingzhengVoice/` 文件夹。若还没有自己的 GitHub/Origin 仓库，先点 **Create repo**，再 Clone 到 Mac 上打开。

## 怎么编辑

**日常改功能：Xcode（推荐）**

```bash
open QingzhengVoice.xcodeproj
```

左侧 Project Navigator 就是全部 Swift 代码。改完 ⌘R 运行。

**也可以用 Cursor 编辑 `.swift` 文件**，但运行、签名、打包仍要 Xcode。

## 需要什么

- 一台 Mac（这是原生 App，不能在网页里预览）
- macOS 14 或更高（macOS 26+ 走 `SpeechAnalyzer`，更早走 `SFSpeechRecognizer`）
- Xcode 16.2 或更高。App Store 里的最新 Xcode 需要 macOS 26.6；系统更旧时，到 [Apple Developer 下载页](https://developer.apple.com/download/all/) 安装与当前系统匹配的 Xcode。Xcode 16 会使用 `SFSpeechRecognizer`；Xcode 26 才会编译设备端 `SpeechAnalyzer`。
- 麦克风、语音识别、辅助功能三项权限

## 运行

1. Xcode 顶部 Signing & Capabilities 选自己的 Team（没有开发者账号就选 Sign to Run Locally）。
2. ⌘R。菜单栏出现波形/麦克风图标。
3. 点图标 →「授予权限」，系统设置里勾选「清正语音」。
4. **先点菜单栏「授予权限」**，等菜单显示「模型就绪」。再把光标放到 Notes、Safari、微信等输入框，按 **Control-Option-空格** 说话，再按一次插入。菜单打开时焦点在自己身上，这时用按钮开始会写回**上一个外部输入框**。macOS 26 单次最长约 5 分钟；更早系统的语音接口大约 55 秒会自动结束。

启动时会预热本地 ASR（下载中文模型 + `modelRetention: lingering`），所以热键按下后应马上开始听，而不是现场加载。系统文本框优先用辅助功能在光标处写字；Chrome / Electron 等网页框退回对目标进程发送 ⌘V。密码框不会插入。

没有 API Key 也能用：本地规则会处理「句号 / 逗号 / 换行」。书面语整理可在设置里填 OpenAI 兼容的 Base URL / Model / Key。

## 怎么打包成 .app

1. Xcode 菜单 **Product → Archive**（先把 scheme 设成 Any Mac / My Mac，配置 Release）。
2. Organizer 出现归档后，点 **Distribute App**。
3. 自己用选 **Copy App**，导出文件夹里就是 `QingzhengVoice.app`，拖到「应用程序」即可。
4. 要发给别人：需要 Apple Developer 账号，选 Developer ID 签名，否则别人打开会提示未验证开发者（系统设置 → 隐私与安全性里仍可「仍要打开」）。

命令行等价：

```bash
xcodebuild -scheme QingzhengVoice -configuration Release -archivePath build/QingzhengVoice.xcarchive archive
xcodebuild -exportArchive -archivePath build/QingzhengVoice.xcarchive -exportPath dist -exportOptionsPlist ExportOptions.plist
```

本地自己用不必走命令行，Archive + Copy App 就够。
