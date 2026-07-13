#!/bin/zsh
# 把 xcodebuild 的 Release 产物组装成可分发的 Qwen3 TTS.app
# 用法: scripts/package-app.sh [--skip-build]
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

PRODUCTS=.xcbuild/Build/Products/Release
APP=dist/Qwen3\ TTS.app
# 版本号取自最近的 git tag（v0.1.0 → 0.1.0），可用 VERSION 环境变量覆盖；
# CFBundleVersion 用提交计数，保证每次发布单调递增
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ "${1:-}" != "--skip-build" ]]; then
  echo "==> xcodebuild Release"
  xcodebuild build -scheme Qwen3TTSApp -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .xcbuild -clonedSourcePackagesDirPath .build \
    -skipPackagePluginValidation -skipMacroValidation -quiet
fi

[[ -x "$PRODUCTS/Qwen3TTSApp" ]] || { echo "找不到构建产物 $PRODUCTS/Qwen3TTSApp"; exit 1; }

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$PRODUCTS/Qwen3TTSApp" "$APP/Contents/MacOS/"
# SPM 资源 bundle（含 mlx-swift_Cmlx.bundle 里的 default.metallib）放进 Resources，
# SPM 生成的 bundle 定位代码会在 Bundle.main.resourceURL 下查找
for bundle in "$PRODUCTS"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
cp assets/icon/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Qwen3 TTS</string>
    <key>CFBundleDisplayName</key><string>Qwen3 TTS</string>
    <key>CFBundleIdentifier</key><string>dev.leolu.qwen3-tts</string>
    <key>CFBundleExecutable</key><string>Qwen3TTSApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 leolu</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP" && echo "签名校验通过"

echo "==> 打 zip 并生成校验"
ZIP="dist/Qwen3TTS-v${VERSION}-arm64.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

echo "==> 完成: $APP"
du -sh "$APP"
ls -lh "$ZIP"
cat "$ZIP.sha256"
