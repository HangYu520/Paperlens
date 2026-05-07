# PaperLens

**极简 macOS 论文翻译助手** — 在本地应用中选中英文，自动翻译为中文。

---

## 功能

- 选中英文 → 自动翻译（Preview、WPS 等本地应用）
- AXObserver 实时检测文本选中
- 自定义 LLM API（DeepSeek、OpenAI 等兼容接口）
- 详细翻译模式：术语标注 + 句式解析 + 学术背景
- 极简界面：仅菜单栏图标 + 浮动气泡
- 快捷键 `⌘⇧T` 一键开关

---

## 安装

### 下载 .app

从 [Releases](https://github.com/HangYu520/PaperLens/releases) 下载最新 `PaperLens-v1.0.zip`，解压后拖入 `/Applications`，双击运行。

### 从源码编译

```bash
git clone https://github.com/HangYu520/PaperLens.git
cd PaperLens
bash build.sh
open PaperLens.app
```

**编译要求**：macOS 14.0+，Command Line Tools（`xcode-select --install`）。

如遇 `SwiftBridging` 模块重复定义错误：
```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap.bak
```

---

## 使用

1. **启动**：双击 `PaperLens.app`，菜单栏出现图标
2. **授权**：首次启动自动弹出设置窗口 → 填入 API Key → 按提示授予辅助功能权限（**前置条件**，否则无法检测文本选中）
3. **翻译**：在 Preview / WPS 等本地应用中选中英文即可
4. **详细翻译**：设置中启用「详细翻译」获得术语标注和句式解析

> ⚠️ 每次重新编译后签名会变化，需重新去 **系统设置 → 隐私与安全性 → 辅助功能** 移除旧条目并添加新 `.app`。

| 菜单栏图标 | 状态 |
|-----------|------|
| 蓝色 | 激活中 |
| 灰色 | 暂停 |

---

## 配置

| 设置项 | 说明 |
|--------|------|
| API Key | DeepSeek / OpenAI 等兼容 API 的 Key |
| 模型 | 默认为 `deepseek-chat`，支持自定义 |
| 详细翻译 | 开启后返回术语标注、句式解析和学术背景 |
| 选中后自动翻译 | 开启后选中即翻译，关闭后显示浮动按钮 |
| 测试连接 | 验证 API Key 是否有效 |

---

## 技术栈

- Swift 6.1 / SwiftUI / AppKit
- Accessibility API（AXObserver）
- DeepSeek API（兼容 OpenAI 格式）
- 零外部依赖，仅系统框架

---

## 项目结构

```
Sources/
├── App.swift              # 主入口 + 菜单栏
├── TextMonitor.swift       # AXObserver 文本选中
├── Translator.swift        # API 客户端
├── TranslationBubble.swift # 翻译气泡
├── FloatingButton.swift    # 浮动按钮
├── SettingsView.swift      # 设置窗口
└── Keychain.swift          # Key 安全存储
build.sh                    # 编译脚本
```

---

## License

MIT
