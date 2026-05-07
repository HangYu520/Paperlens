# PaperLens — 设计文档

## 概述

一个极简的 macOS 原生工具，帮助你在阅读英文 PDF 论文时，选中文字即可一键翻译。基于 Swift/SwiftUI，翻译后端使用 DeepSeek API。

---

## 核心交互

```
用户阅读 PDF（Preview / Chrome / 任意应用）
    │
    选中英文段落
    │
    ▼
┌────────┐
│   🌐   │  浮动圆形按钮（36pt），出现在选中文字附近
└────────┘
    │  5秒未点击自动消失
    ▼  点击
┌──────────────────┐
│ 注意力机制通过...  │  翻译气泡
│                  │  只显示译文（原文你正在看）
│         📋   ✕   │  复制 + 关闭
└──────────────────┘
    │
    点击气泡外部 → 消失
```

**仅 3 个界面元素:**
- 菜单栏图标（激活/暂停）
- 悬浮翻译按钮
- 翻译气泡

---

## 状态控制

| 操作 | 效果 |
|------|------|
| 点击菜单栏图标 | 切换 激活 ↔ 暂停 |
| `Cmd+Shift+T` | 全局快捷键切换 |
| 菜单栏图标 | 蓝色 = 激活，灰色 = 暂停 |
| 全屏应用 | 自动暂停（避免干扰） |
| 重启应用 | 记住上次的激活状态 |

暂停时: AXObserver 完全停止，无任何弹窗，零干扰。

---

## 菜单栏

```
         🧠  (灰/蓝)
           │
     ┌─────▼──────┐
     │ ● 翻译模式  │   点击切换
     │ ────────── │
     │ ⚙️ 设置     │
     │ ────────── │
     │ ❌ 退出     │
     └────────────┘
```

---

## 翻译气泡规格

```
         ┌──────────────────────┐
         │ 注意力机制通过计算查询 │
         │ 和键之间的相似度，允许 │
         │ 模型动态关注输入序列的 │
         │ 不同部分，从而捕捉长距 │
         │ 离依赖关系。          │
         │                      │
         │              📋   ✕  │
         └──────────────────────┘
```

- 最大宽度: 420pt，最大高度: 300pt（超出滚动）
- 只显示译文，不显示原文
- 加载态: 小转圈动画 + "翻译中..."
- 错误态: 错误信息 + 重试
- 背景: `.regularMaterial`（系统毛玻璃）
- 圆角: 12pt，投影: `shadow(radius: 12, y: 4)`

---

## 设置窗口

```
    ┌──────────────────────────┐
    │  设置                    │
    ├──────────────────────────┤
    │                          │
    │  API Key                 │
    │  ┌──────────────────────┐│
    │  │ sk-••••••••••••••••  ││
    │  └──────────────────────┘│
    │                          │
    │  模型                    │
    │  [ deepseek-chat    ▼ ] │
    │                          │
    │  快捷键                  │
    │  [ ⌘⇧T 点击修改 ]       │
    │                          │
    │  ── 版本 1.0            │
    └──────────────────────────┘
```

---

## DeepSeek API 调用

```
POST https://api.deepseek.com/v1/chat/completions

{
  "model": "deepseek-chat",
  "messages": [
    {
      "role": "system",
      "content": "你是一个学术论文翻译助手。将用户提供的英文文本翻译为中文。要求：1. 保持学术论文的专业性和严谨性 2. 术语翻译准确 3. 不添加任何解释或补充 4. 仅输出译文"
    },
    {
      "role": "user",
      "content": "{选中的原文}"
    }
  ],
  "temperature": 0.3,
  "max_tokens": 4096
}
```

- temperature = 0.3: 保证术语一致性
- 超时: 30s
- 重试: 失败自动重试 1 次
- API Key 存储在 Keychain（不落盘明文）

---

## 技术要点

### Accessibility API 监听文本选中

```swift
// 获取前台应用 → 注册 AXObserver → 监听 kAXSelectedTextChangedNotification
// 获取选中文本 + 选中区域的屏幕坐标
AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute, &text)
AXUIElementCopyParameterizedAttributeValue(element, 
    kAXBoundsForRangeParameterizedAttribute, range, &bounds)
```

- 需要在「系统设置 → 辅助功能」中授权
- Preview.app / Chrome / Safari 等主流应用支持良好

### 浮动按钮定位

- 基于 `AXBoundsForRange` 获取选中区域坐标
- 按钮显示在选中区域右上角偏移 (+8pt, -8pt)
- 智能边界检测: 靠近屏幕边缘时自动反向定位

---

## 错误处理

| 场景 | 气泡显示 |
|------|---------|
| 未配置 API Key | "请先在设置中配置 API Key" |
| API Key 无效 (401) | "API Key 无效，请检查" |
| 网络不通 | "无网络连接" + 重试按钮 |
| 超时 (30s) | "翻译超时，请重试" |
| 限流 (429) | "请求频繁，请稍后" + 3s 自动重试 |
| 选中为空 / 内容过长(>5000) | 不触发 / 截断提示 |

---

## 文件结构

```
PaperLens/
├── App.swift                  // @main 入口 + 菜单栏
├── TextMonitor.swift          // AXObserver 选中检测
├── Translator.swift           // DeepSeek API 调用
├── FloatingButton.swift       // 浮动按钮
├── TranslationBubble.swift    // 翻译气泡
├── SettingsView.swift         // 设置窗口
├── Keychain.swift             // API Key 安全存储
└── Info.plist
```

**7 个文件。**

---

## 开发阶段

| 步 | 内容 | 产出 |
|---|------|------|
| 1 | 骨架: 菜单栏 + 设置窗口 + Keychain | 应用可见，可配 Key |
| 2 | 翻译: DeepSeek API + 气泡 UI | 可手动输入文本翻译 |
| 3 | 监听: AXObserver + 浮动按钮 + 完整交互 | 产品可用 |

---

## 不做

- 翻译历史 / 侧边面板
- 手动模式降级（过度边缘场景）
- 流式输出（学术段落短，不需要逐字显示）
- 翻译结果缓存（论文场景不重复翻）
- 应用排除列表 UI（用暂停快捷键替代）
- Token 用量统计
