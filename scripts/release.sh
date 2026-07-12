#!/bin/zsh
# 发布打包：完整构建 → .app → zip + 校验和 → 提示 gh release 命令
# 用法: scripts/release.sh <version>   如 scripts/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?用法: scripts/release.sh <version>（如 0.1.0）}
export VERSION

echo "==> 打包 v$VERSION"
scripts/package-app.sh

ZIP="Qwen3TTS-v$VERSION-arm64.zip"
cd dist
rm -f "$ZIP" "$ZIP.sha256"
# ditto 保留 resource fork 与签名，是分发 .app 的标准压缩方式
ditto -c -k --sequesterRsrc --keepParent "Qwen3 TTS.app" "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"
cd ..

echo ""
echo "==> 产物"
ls -lh "dist/$ZIP"
cat "dist/$ZIP.sha256"
echo ""
echo "==> 发布（需已 gh auth login 且仓库有 origin）"
echo "  git tag v$VERSION && git push origin main --tags"
echo "  gh release create v$VERSION dist/$ZIP dist/$ZIP.sha256 --title 'v$VERSION' --notes-file <notes.md>"
