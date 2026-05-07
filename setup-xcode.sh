#!/bin/bash
# PaperLens Xcode 项目快速创建脚本
# 用法: bash setup-xcode.sh
# 前置: 已安装 Xcode

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "==> 在 $PROJECT_DIR 创建 Xcode 项目..."

# 创建项目目录结构
mkdir -p "$PROJECT_DIR/PaperLens.xcodeproj"

# 生成 project.pbxproj (简化版，使用 swift package generate-xcodeproj)
# 更简单的方式：直接用 SPM 生成
cd "$PROJECT_DIR"

if [ -f Package.swift ]; then
    echo "==> 使用 SPM 生成 Xcode 项目..."
    swift package generate-xcodeproj 2>/dev/null || {
        echo "⚠️  swift package generate-xcodeproj 不可用"
        echo "请使用 Xcode 打开 Package.swift (File → Open → 选择 Package.swift)"
        echo "或者在 Xcode 中创建新项目并将 Sources/ 目录下的文件添加进去"
        echo ""
        echo "手动创建步骤:"
        echo "1. Xcode → New Project → macOS → App"
        echo "2. Interface: SwiftUI, Language: Swift"
        echo "3. 删除自动生成的 ContentView.swift 和 AppNameApp.swift"
        echo "4. 将 Sources/ 下所有 .swift 文件拖入项目"
        echo "5. Info.plist 中设置 LSUIElement = YES"
        echo "6. Build & Run"
    }
fi
