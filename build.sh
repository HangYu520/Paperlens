#!/bin/bash
set -euo pipefail

APP_NAME="PaperLens"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> 清理旧构建..."
rm -rf "$APP_DIR" "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"

echo "==> 编译 Swift 源文件 ($(swift --version | head -1))..."
cd "$SOURCES_DIR"

swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    -O \
    -framework SwiftUI \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Security \
    -framework Foundation \
    -o "$BUILD_DIR/$APP_NAME" \
    Keychain.swift \
    Translator.swift \
    SettingsView.swift \
    TranslationBubble.swift \
    FloatingButton.swift \
    TextMonitor.swift \
    ClipboardDetector.swift \
    App.swift

echo "==> 创建 .app bundle..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>PaperLens</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.paperlens.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PaperLens</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>PaperLens</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [ -f "$PROJECT_DIR/icon.icns" ]; then
    echo "==> 复制图标..."
    cp "$PROJECT_DIR/icon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "==> Ad-hoc 签名..."
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo ""
echo "✅ 构建完成: $APP_DIR ($SIZE)"
echo ""
echo "运行方式:"
echo "  open $APP_DIR"
echo ""
echo "首次使用:"
echo "  1. 系统设置 → 隐私与安全性 → 辅助功能 → 添加 PaperLens"
echo "  2. 菜单栏点击 🧠 → 设置 → 填入 DeepSeek API Key"
echo "  3. 在任意 PDF 阅读器中选中英文 → 自动显示翻译"
