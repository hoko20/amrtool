#!/usr/bin/env bash
#
# 生成 Xcode 工程并打包无签名 / ad-hoc IPA 到 build/
#

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：构建 iOS IPA 需要 macOS + Xcode（当前系统：$(uname -s)）。" >&2
  echo "请在 Mac 上执行本脚本，或推送到 GitHub 由 Actions 自动构建。" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
APP_NAME="AudioForge"

mkdir -p "$BUILD"
rm -rf "$BUILD/$APP_NAME.xcarchive" "$BUILD/ipa" "$BUILD/adhoc" "$BUILD/$APP_NAME-unsigned.ipa" "$BUILD/$APP_NAME-adhoc.ipa"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，请先执行: brew install xcodegen" >&2
  exit 1
fi

if [[ ! -f "$ROOT/Vendor/lib/libopencore-amrnb.a" || \
      ! -f "$ROOT/Vendor/lib/libvo-amrwbenc.a" || \
      ! -f "$ROOT/Vendor/lib/libSKP_SILK_SDK.a" ]]; then
  echo "==> Vendor 静态库缺失，先构建编码器"
  "$ROOT/Scripts/build-opencore-amr.sh"
fi

echo "==> 生成 Xcode 工程"
xcodegen generate --spec "$ROOT/project.yml"

echo "==> 归档"
set -o pipefail
xcodebuild \
  -project "$ROOT/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$BUILD/$APP_NAME.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  archive | tee "$BUILD/xcodebuild.log"

APP="$BUILD/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
  echo "归档产物缺失: $APP" >&2
  exit 1
fi

echo "==> 打包无签名 IPA"
mkdir -p "$BUILD/ipa/Payload"
cp -R "$APP" "$BUILD/ipa/Payload/"
( cd "$BUILD/ipa" && zip -qry -X "$BUILD/$APP_NAME-unsigned.ipa" Payload )

echo "==> 打包 ad-hoc IPA"
mkdir -p "$BUILD/adhoc/Payload"
cp -R "$APP" "$BUILD/adhoc/Payload/"
if codesign --force --deep --sign - "$BUILD/adhoc/Payload/$APP_NAME.app"; then
  ( cd "$BUILD/adhoc" && zip -qry -X "$BUILD/$APP_NAME-adhoc.ipa" Payload )
  shasum -a 256 "$BUILD/$APP_NAME-unsigned.ipa" "$BUILD/$APP_NAME-adhoc.ipa" > "$BUILD/sha256.txt"
else
  echo "ad-hoc 签名失败，仅保留无签名 IPA" >&2
  shasum -a 256 "$BUILD/$APP_NAME-unsigned.ipa" > "$BUILD/sha256.txt"
fi

{
  echo "AudioForge 构建报告"
  echo "时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
  echo
  echo "产物:"
  ls -lh "$BUILD"/*.ipa
  echo
  echo ".app 大小: $(du -sh "$APP" | cut -f1)"
  echo "版本: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo '1.0.0')"
} > "$BUILD/build-report.txt"

cat "$BUILD/build-report.txt"
