# PaperLens — 实现计划

## 1. 目标

构建一个极简 macOS 原生应用：在任意应用中选中英文文字，点击悬浮按钮，通过 DeepSeek API 翻译为中文。7 个源文件，无外部依赖（除系统框架）。

---

## 2. 文件清单

| 文件 | 操作 | 内容 |
|------|------|------|
| `PaperLens.xcodeproj` | 创建 | Xcode 项目（macOS App, SwiftUI） |
| `App.swift` | 创建 | @main 入口 + MenuBarExtra + 状态管理 |
| `TextMonitor.swift` | 创建 | AXObserver 封装，检测前台应用文本选中 |
| `Translator.swift` | 创建 | DeepSeek API 客户端，发送请求/解析响应 |
| `FloatingButton.swift` | 创建 | 悬浮圆形按钮 + 智能定位 |
| `TranslationBubble.swift` | 创建 | 翻译结果气泡（加载/结果/错误三态） |
| `SettingsView.swift` | 创建 | 设置窗口（API Key / 模型 / 快捷键） |
| `Keychain.swift` | 创建 | API Key 安全读写 |
| `Info.plist` | 修改 | 添加 LSUIElement（隐藏 Dock 图标） |

**依赖**: 仅系统框架 — SwiftUI, AppKit, ApplicationServices, Security, Foundation

---

## 3. 分步任务

---

### Step 1: 创建 Xcode 项目骨架

**操作:**
```bash
# 创建 macOS SwiftUI 项目
# App 类型: MenuBarExtra (LSUIElement = true)
# Bundle ID: com.paperlens.app
# 最低部署: macOS 14.0
```

**产出:**
- `PaperLens.xcodeproj` 可编译运行
- `Info.plist` 含 `LSUIElement = YES`（Dock 无图标，仅菜单栏）
- `App.swift` 有空的 `MenuBarExtra` 入口

**验证:**
- 应用启动后 Dock 无图标
- 菜单栏出现占位图标
- `Cmd+Q` 可退出

---

### Step 2: App.swift — 主入口 + 状态管理

**实现内容:**
- `@main struct PaperLensApp: App`
- `@AppStorage("isMonitoringEnabled")` 持久化激活状态
- `MenuBarExtra` 显示图标，根据 `isMonitoringEnabled` 切换颜色
- 菜单项: "●/○ 翻译模式"（切换）、分隔线、"设置..."、"退出"
- `@State var showSettings = false` 控制设置窗口
- `nskeyboard` 全局快捷键 `Cmd+Shift+T` 注册（使用 `NSEvent.addGlobalMonitorForEvents`）
- 全屏检测: `NSWorkspace.shared.frontmostApplication` 结合 `CGWindowListCopyWindowInfo` 检测全屏

**状态模型:**
```
isMonitoringEnabled (AppStorage持久化)
       │
       ├── true  → 图标蓝色 → TextMonitor 运行
       │          → 但如果「全屏」则自动暂停（内部标志）
       │
       └── false → 图标灰色 → TextMonitor 停止 → 无任何监听
```

**产出:** `App.swift` (~120 行)

**依赖:** Step 1

---

### Step 3: Keychain.swift — API Key 安全存储

**实现内容:**
- `KeychainManager` struct
- `static func save(key: String)` / `static func load() -> String?` / `static func delete()`
- 使用 `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`
- service name: `"com.paperlens.apikey"`
- 错误处理: 如果读取失败返回 nil（不是 crash）

**产出:** `Keychain.swift` (~50 行)

**验证:**
- 写入 → 重启应用 → 读取成功
- 删除后读取返回 nil

---

### Step 4: SettingsView.swift — 设置窗口

**实现内容:**
- `struct SettingsView: View`
- API Key 输入区: `SecureField` + 显示/隐藏切换 + Keychain 读写
- 模型选择: `Picker` 选项 `["deepseek-chat"]`（预留扩展）
- 快捷键显示: 静态文本 `⌘⇧T`（v1.0 不自定义）
- 底部版本号 `"版本 1.0"`
- 窗口打开时从 Keychain 加载当前 Key
- 失焦/关闭时自动保存到 Keychain

**布局:**
```
VStack(spacing: 20) {
    标题: "设置"
    API Key 输入框
    模型选择器
    快捷键显示
    Divider()
    版本号
}
.frame(width: 340, height: 280)
```

**产出:** `SettingsView.swift` (~80 行)

**依赖:** Step 3

---

### Step 5: Translator.swift — DeepSeek API 客户端

**实现内容:**
```swift
class TranslatorService {
    static let shared = TranslatorService()
    
    func translate(_ text: String, apiKey: String, model: String) async throws -> String
    func cancelCurrent()
}
```

**详细逻辑:**
- `URLSession` 异步请求 `https://api.deepseek.com/v1/chat/completions`
- 请求体: `system prompt` + `user text`，`temperature=0.3`，`max_tokens=4096`
- 超时: 30s（`URLSessionConfiguration.timeoutIntervalForRequest = 30`）
- 错误分类: 无网络 / 401 / 429 / 超时 / 通用 → 各自返回不同的 `TranslationError`
- 取消支持: `URLSessionTask.cancel()`，通过 `Task.checkCancellation()` 传播
- 响应解析: `Codable` 模型 `DeepSeekResponse`，提取 `choices[0].message.content`
- 重试: 失败后自动重试 1 次（1s 延迟），`429` 等待 3s

**TranslationError 枚举:**
```swift
enum TranslationError: LocalizedError {
    case noAPIKey
    case invalidAPIKey       // 401
    case noNetwork
    case rateLimited         // 429
    case timeout
    case unknown(String)
}
```

**产出:** `Translator.swift` (~100 行)

**依赖:** Step 3 (Keychain for API key reading)

**验证:**
- 配置有效 Key → 翻译成功
- 配置无效 Key → 显示 "API Key 无效"
- 断网 → 显示 "无网络连接"

---

### Step 6: TranslationBubble.swift — 翻译气泡

**实现内容:**
- `struct TranslationBubbleView: View`
- 三态: `.idle`（初始）/ `.loading`（翻译中）/ `.result(String)`（结果）/ `.error(TranslationError)`（失败）

**各态 UI:**
- **loading**: `ProgressView()` + "翻译中..."，带取消按钮
- **result**: 译文文本（`Text`，可选复制）+ 📋复制按钮 + ✕关闭按钮
- **error**: 错误描述 + "重试"按钮 + ✕关闭按钮

**交互:**
- 📋 复制按钮: `NSPasteboard.general.clearContents()` + `setString(translatedText, forType: .string)`
- ✕ 关闭: dismiss 气泡
- 点击气泡外部: dismiss（通过 `.overlay` + `Color.clear.onTapGesture`）

**规格:**
- `maxWidth: 420`, `maxHeight: 300`
- `padding: 16`
- `background: .regularMaterial`
- `cornerRadius: 12`
- `shadow(radius: 12, y: 4)`

**产出:** `TranslationBubble.swift` (~150 行)

**依赖:** Step 5

---

### Step 7: FloatingButton.swift — 浮动按钮

**实现内容:**
- `struct FloatingButtonView: View`
- 36×36pt 圆形按钮，白色背景，阴影
- SF Symbol: `"globe"` 或 `"character.book.closed"`
- 出现动画: `scale(0.8) + opacity(0)` → `scale(1.0) + opacity(1)`，200ms spring
- 消失动画: `scale(0.8) + opacity(0)`，150ms easeOut
- 点击回调: `onTap: () -> Void`
- 5 秒未点击自动消失

**定位逻辑 (PositionCalculator):**
```swift
// 输入: 选中区域 bounds (AXBoundsForRange 返回)
// 输出: 按钮的 NSPoint (screen coordinates)
// 逻辑:
//   1. 默认: 选中区域右上角 + (8, -8) 偏移
//   2. 如果超出屏幕右边界 → 放在左侧
//   3. 如果超出屏幕顶边界 → 放在下方
```

**窗口管理:**
- 使用独立的 `NSWindow`（非 SwiftUI 原生窗口）
- `level = .floating`（高于普通窗口）
- `collectionBehavior = [.canJoinAllSpaces, .stationary]`（跨桌面显示）
- `isOpaque = false`，`backgroundColor = .clear`
- 无标题栏 `styleMask = [.borderless, .nonactivating]`

**产出:** `FloatingButton.swift` (~180 行)

**依赖:** 独立（可在 Step 3 后开始，只需位置传入）

---

### Step 8: TextMonitor.swift — 文本选中监听

**实现内容:**
```swift
class TextMonitor {
    private var observer: AXObserver?
    private var currentPID: pid_t?
    
    func startMonitoring()
    func stopMonitoring()
    
    var onTextSelected: ((String, NSRect) -> Void)?
}
```

**详细逻辑:**
1. 使用 `NSWorkspace.shared.notificationCenter` 监听 `NSWorkspace.didActivateApplicationNotification`
2. 当应用切换时:
   - 停止旧的 AXObserver
   - 为新应用创建 AXObserver，注册 `kAXSelectedTextChangedNotification`
3. 回调触发时:
   - 获取 `kAXSelectedTextAttribute`（选中文本）
   - 获取 `kAXBoundsForRangeParameterizedAttribute`（选中区域坐标）
   - 过滤: 空字符串 / 纯数字 / 长度 > 5000 跳过
   - 调用 `onTextSelected` 回调

**AXObserver 管理:**
```swift
// C API 桥接
AXObserverCreate(pid, { observer, element, notification, refcon in
    // 回调
}, &observer)

AXObserverAddNotification(observer, appElement, 
    kAXSelectedTextChangedNotification as CFString, nil)

CFRunLoopAddSource(CFRunLoopGetCurrent(), 
    AXObserverGetRunLoopSource(observer), .defaultMode)
```

**辅助功能权限检查:**
```swift
let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
AXIsProcessTrustedWithOptions(options)
```

**产出:** `TextMonitor.swift` (~150 行)

**依赖:** 独立（纯 AppKit + C API）

---

### Step 9: 整合 — App.swift 串联所有模块

**在 `App.swift` 中整合:**

```
PaperLensApp
  │
  ├── MenuBarExtra (菜单栏图标 + 菜单)
  │
  ├── TextMonitor 实例
  │   └── onTextSelected → 显示 FloatingButton
  │
  ├── FloatingButton 窗口管理
  │   └── onTap → 显示 TranslationBubble + 调用 Translator
  │
  ├── TranslationBubble 窗口管理
  │   └── 调用 TranslatorService.shared.translate()
  │
  ├── SettingsView (modally presented)
  │
  └── NSEvent.addGlobalMonitorForEvents (快捷键)
```

**状态流:**
```
TextMonitor.onTextSelected(text, bounds)
    → 创建 FloatingButton window，定位到 bounds 附近
    → 5s timer 启动
    
FloatingButton.onTap
    → 隐藏按钮
    → 创建 TranslationBubble window，定位在原按钮位置下方
    → 调用 TranslatorService.shared.translate(text)
    → 结果返回后更新 bubble 状态

TranslationBubble 关闭
    → 关闭 bubble 窗口
    
菜单栏 / 快捷键切换
    → isMonitoringEnabled.toggle()
    → 如 false: TextMonitor.stopMonitoring() + 关闭所有浮动窗口
    → 如 true: TextMonitor.startMonitoring()
```

**产出:** 更新 `App.swift` (~180 行 → 整合后约 300 行)

**依赖:** Step 2, 5, 6, 7, 8

---

### Step 10: 打磨 & 测试

**待完成:**
- [ ] 全屏检测逻辑验证（用 QuickTime Player 录屏模式测试）
- [ ] 无 API Key 时点击翻译 → 气泡显示引导文字
- [ ] 翻译超时 30s → 气泡显示错误
- [ ] 快速连续选中 → 旧浮动按钮消失，新按钮出现
- [ ] 跨桌面场景（Mission Control 切换桌面后按钮仍可见）
- [ ] 睡眠唤醒后 AXObserver 恢复
- [ ] 首次启动辅助功能权限引导弹窗
- [ ] `Cmd+Q` 正确退出，清理 AXObserver 资源

---

## 4. 测试策略

由于是极简工具，采用手动验证矩阵：

| 场景 | 预期 |
|------|------|
| 打开 Preview.app，选中 PDF 中文字 | 浮动按钮出现 |
| 点击按钮 | 气泡显示翻译中 → 显示中文翻译 |
| 点击复制按钮 | 译文复制到剪贴板 |
| 点击气泡外部 | 气泡消失 |
| 菜单栏切换至暂停 | 选中文字无反应，图标灰色 |
| `Cmd+Shift+T` 切换 | 菜单栏图标切换，功能开关 |
| 在 Chrome 选中网页文字 | 浮动按钮出现 |
| API Key 为空时翻译 | 气泡引导配置 |
| 无网络时翻译 | 气泡显示错误 + 重试按钮 |
| 全屏 YouTube 播放时选中文字 | 无反应（自动暂停） |

---

## 5. 验证标准

- [ ] 应用在 macOS 14+ 上编译通过，无 warning
- [ ] 菜单栏图标正确显示，点击菜单项功能正常
- [ ] `LSUIElement` 生效，Dock 无图标
- [ ] 在 Preview / Chrome / Safari 中选中文字均能触发浮动按钮
- [ ] 浮动按钮位置准确（不出现在屏幕外）
- [ ] DeepSeek API 翻译返回正确中文
- [ ] API Key 存储在 Keychain，重启后仍可读取
- [ ] 暂停状态下完全静默，零弹窗
- [ ] 内存占用 < 50MB（空闲状态）

---

## 6. 执行顺序依赖图

```
Step 1 (项目骨架)
    │
    ├── Step 2 (App.swift 基础)
    │       │
    │       └── Step 9 (整合) ─── Step 10 (打磨)
    │
    ├── Step 3 (Keychain) 
    │       │
    │       ├── Step 4 (SettingsView)
    │       │
    │       └── Step 5 (Translator)
    │               │
    │               └── Step 6 (TranslationBubble)
    │
    ├── Step 7 (FloatingButton) ──────────┐
    │                                      │
    └── Step 8 (TextMonitor) ──────────────┤
                                           │
    Step 3─6 和 Step 7─8 可并行            │
                                           ▼
                                     Step 9 (整合)
```
