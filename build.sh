#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeyLite"
BUNDLE_ID="com.bruce.keylite"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

echo "==> 0. 安全退出正在运行的 KeyLite（确保内核安全释放 EventTap，防止触控板/鼠标冻结）"
killall -9 "${APP_NAME}" 2>/dev/null || true
sleep 0.5

echo "==> 1. 清理并准备构建目录"
rm -rf "$BUILD_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

echo "==> 2. 生成应用图标"
if [ ! -f "Resources/icon.icns" ]; then
    python3 make_icon.py
fi
cp Resources/icon.icns "${APP_DIR}/Contents/Resources/"

echo "==> 3. 生成完整 Info.plist"
cat << EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>icon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.0</string>
    <key>CFBundleVersion</key>
    <string>4</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>KeyLite 需要通过系统事件触发快捷键模拟与锁屏功能。</string>
</dict>
</plist>
EOF

echo "==> 4. 编译 Swift 源码"
swiftc -O \
    -target arm64-apple-macosx13.0 \
    Sources/Models/*.swift \
    Sources/Core/*.swift \
    Sources/UI/*.swift \
    Sources/main.swift \
    -o "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo "==> 5. 严格代码签名"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> 6. 部署到 /Applications/"
rm -rf "$DEST"
ditto "$APP_DIR" "$DEST"
codesign --force --deep --sign - "$DEST"
touch "$DEST"

echo "==> 7. 启动新版本 KeyLite"
open "$DEST"

echo "==> 🎉 构建与部署成功: $DEST"
