# 清正语音

给清正在 Mac 上用的系统级中英语音输入。菜单栏常驻：说话 → 本地转写 → 整理文本 → 插入当前应用光标处。不是拼音输入法。

## 需要什么

- macOS 14 或更高（macOS 26+ 会用设备端 `SpeechAnalyzer`，更早系统走 `SFSpeechRecognizer`）
- Xcode 26 或更高（才能编译新的 Speech API）
- 麦克风、语音识别、辅助功能三项权限

## 在 Mac 上运行

```bash
open QingzhengVoice.xcodeproj
```

1. 在 Xcode 里选自己的 Signing Team（或 Sign to Run Locally）。
2. Run（⌘R）。菜单栏出现波形/麦克风图标。
3. 点图标，按「授予权限」，并在系统设置里勾选「清正语音」。
4. 第一次说中文时，系统可能下载设备端语音模型，需要网络一次。
5. 把光标放到 Notes、浏览器、聊天框等目标里，按 **Control-Option-空格** 开始，说完再按一次。文本会粘贴到光标处。

没有 API Key 也能用完整流程：整理器默认把「句号 / 逗号 / 换行」等口播指令变成标点，并去掉常见口头禅。若要更像书面语，打开设置，填 OpenAI 兼容的 Base URL、Model 和 Key（官方接口或 DeepSeek 均可）。

## 这一刀包含什么

- 全局热键开始/结束录音，不抢当前应用焦点
- 本地优先语音识别，中文为主、英文可说
- 可插拔文本整理：本地规则 / Apple Intelligence / OpenAI 兼容接口
- 剪贴板 + ⌘V 插入焦点应用，并恢复原来的剪贴板

## 这一刀不包含什么

- InputMethodKit 拼音输入法
- 内置 whisper.cpp 模型（下一步才接）
- 自定义快捷键面板、登录时启动
