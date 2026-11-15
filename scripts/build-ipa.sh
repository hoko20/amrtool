#!/usr/bin/env bash
# 在 macOS runner 上生成工程、编译并打包无签名 IPA（可交给 AltStore / SideStore / 自签工具重签）。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DERIVED="$ROOT/build/derived"
STAGE="$ROOT/build/stage"
APPNAME="AMRConverter.app"
IPA="$ROOT/build/AMRConverter-unsigned.ipa"

if [ ! -f "$ROOT/Vendor/lib/libopencore-amrnb.a" ]; then
  echo "缺少 Vendor/lib/libopencore-amrnb.a，先执行 scripts/build-opencore-amr.sh" >&2
  exit 1
fi

echo "== 工具链 =="
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version

echo "== 生成工程 =="
xcodegen generate --spec project.yml

echo "== 编译 =="
BUILD_ARGS=(
  -project "$ROOT/AMRConverter.xcodeproj"
  -scheme AMRConverter
  -configuration Release
  -sdk iphoneos
  -destination 'generic/platform=iOS'
  -derivedDataPath "$DERIVED"
  CODE_SIGNING_ALLOWED=NO
)
if [ -n "${DEPLOYMENT_TARGET:-}" ]; then
  BUILD_ARGS+=("IPHONEOS_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET")
  echo "部署目标覆盖：$DEPLOYMENT_TARGET"
fi
BUILD_ARGS+=(build)
xcodebuild "${BUILD_ARGS[@]}"

PRODUCT="$DERIVED/Build/Products/Release-iphoneos/$APPNAME"
if [ ! -d "$PRODUCT" ]; then
  echo "找不到产物：$PRODUCT" >&2
  exit 1
fi

echo "== 打包 =="
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$PRODUCT" "$STAGE/Payload/$APPNAME"

# 目标架构检查
lipo -info "$STAGE/Payload/$APPNAME/$APPNAME"

# adhoc 签名：方便部分安装器识别，普通真机安装仍需重签
if codesign --force --sign - --timestamp=none "$STAGE/Payload/$APPNAME" 2>/dev/null; then
  codesign --verify --deep --strict "$STAGE/Payload/$APPNAME"
  echo "adhoc 签名完成"
else
  echo "adhoc 签名跳过（保留无签名 IPA）"
fi

rm -f "$IPA"
(cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
/usr/bin/unzip -t "$IPA" > /dev/null
shasum -a 256 "$IPA" | tee "$IPA.sha256"

echo "IPA: $IPA"
