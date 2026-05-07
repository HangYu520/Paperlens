# PaperLens 🔍

**极简 macOS 论文翻译助手** — 在任意应用中选中英文，自动翻译为中文。

*A minimalist macOS research paper translation tool — select English text anywhere, get Chinese translation instantly.*

---

## 功能 / Features

- 🔍 选中英文 → 自动翻译（无需切换窗口）
- 🌐 支持任意应用：Preview、Chrome、Safari、WPS、QQ...
- ⚡ 三种检测模式：AX 通知 / AX 轮询 / 剪贴板监听
- 🔑 自定义 LLM API（DeepSeek、OpenAI 等兼容接口）
- 📋 详细翻译模式：术语标注 + 句式解析 + 学术背景
- 🎨 极简界面：仅菜单栏图标 + 浮动气泡
- ⌨️ 快捷键 `⌘⇧T` 一键开关

---

## 安装 / Installation

### 方式 1：下载 .app（推荐）

从 [Releases](https://github.com/HangYu520/PaperLens/releases) 下载最新 `PaperLens-v1.0.zip`，解压后拖入 `/Applications`，双击运行。

### 方式 2：从源码编译

```bash
git clone https://github.com/HangYu520/PaperLens.git
cd PaperLens
bash build.sh
open PaperLens.app
```

**编译要求**：macOS 14.0+，Command Line Tools（`xcode-select --install`）。

如遇 `SwiftBridging` 模块重复定义错误，执行：
```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap.bak
```

---

## 使用 / Usage

1. **启动**：双击 `PaperLens.app`，菜单栏出现 🔍 图标
2. **授权**：首次启动自动弹出设置窗口 → 填入 API Key → 按提示授予辅助功能权限
3. **翻译**：在任意应用中选中英文文字
   - 支持的应用会自动弹出气泡
   - 不支持自动复制的应用（如 Chrome），手动 `⌘C` 后即触发
4. **详细翻译**：设置中启用「详细翻译」获得术语标注和句式解析

| 菜单栏图标 | 状态 |
|-----------|------|
| 蓝色 `text.bubble.fill` | 激活中 |
| 灰色 `text.bubble` | 暂停 |

---

## 配置 / Configuration

| 设置项 | 说明 |
|--------|------|
| API Key | DeepSeek / OpenAI 等兼容 API 的 Key |
| 模型 | 默认为 `deepseek-chat`，支持自定义 |
| 详细翻译 | 开启后返回术语标注、句式解析和学术背景 |
| 选中后自动翻译 | 开启后选中即翻译，关闭后显示浮动按钮 |
| 测试连接 | 验证 API Key 是否有效 |

---

## 技术栈 / Tech Stack

- Swift 6.1 / SwiftUI / AppKit
- Accessibility API（AXObserver）
- NSPasteboard 剪贴板监听
- DeepSeek API（兼容 OpenAI 格式）
- 零外部依赖，仅系统框架

---

## 项目结构 / Project Structure

```
PaperLens/
├── Sources/
│   ├── App.swift              # 主入口 + 菜单栏 + 状态管理
│   ├── TextMonitor.swift       # AXObserver 文本选中监听
│   ├── ClipboardDetector.swift # 剪贴板监听 + 自动复制
│   ├── Translator.swift        # LLM API 客户端
│   ├── TranslationBubble.swift # 翻译气泡 UI
│   ├── FloatingButton.swift    # 浮动按钮 + 智能定位
│   ├── SettingsView.swift      # 设置窗口
│   └── Keychain.swift          # API Key 安全存储
├── build.sh                    # 一键编译脚本
├── generate-icon.py            # 图标生成脚本
├── icon.icns                   # 应用图标
├── docs/                       # 设计文档
└── README.md
```

---

## License

MIT
