#!/usr/bin/env bash
# 交叉编译 opencore-amr 的 amrnb（含编码器）为 iOS device 静态库。
# 产物：Vendor/lib/libopencore-amrnb.a、Vendor/include/interf_enc.h
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/opencore-amr-build"
MIN_IOS="${MIN_IOS:-26.0}"

rm -rf "$WORK"
mkdir -p "$WORK" "$VENDOR/lib" "$VENDOR/include"

echo "== 获取 opencore-amr 源码 =="
AMR_SRC=""

# 1) SourceForge 官方发布包
if curl -fsSL --retry 3 -o "$WORK/opencore-amr.tar.gz" \
    "https://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz"; then
  tar xzf "$WORK/opencore-amr.tar.gz" -C "$WORK"
  AMR_SRC="$(find "$WORK" -maxdepth 3 -type d -name amrnb | head -1)"
fi

# 2) 回退：GitHub 上的 iOS 移植仓库（内含完整源码）
if [ -z "$AMR_SRC" ]; then
  echo "SourceForge 不可用，改用 GitHub 镜像"
  git clone --depth 1 https://github.com/feuvan/opencore-amr-iOS "$WORK/feuvan"
  AMR_SRC="$(find "$WORK/feuvan" -maxdepth 4 -type d -name amrnb | head -1)"
fi

if [ -z "$AMR_SRC" ] || [ ! -f "$AMR_SRC/interf_enc.c" ]; then
  echo "找不到 amrnb 源码（需要 interf_enc.c）" >&2
  exit 1
fi
echo "源码目录：$AMR_SRC"

echo "== 交叉编译 arm64 =="
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$WORK/obj"

OBJS=()
for source in "$AMR_SRC"/*.c; do
  object="$WORK/obj/$(basename "${source%.c}").o"
  xcrun --sdk iphoneos clang \
    -arch arm64 \
    -isysroot "$SDK" \
    -miphoneos-version-min="$MIN_IOS" \
    -O2 -fPIC -Wno-everything \
    -I"$AMR_SRC" \
    -c "$source" -o "$object"
  OBJS+=("$object")
done

xcrun --sdk iphoneos ar -rcs "$VENDOR/lib/libopencore-amrnb.a" "${OBJS[@]}"
cp "$AMR_SRC/interf_enc.h" "$VENDOR/include/"

echo "== 产物 =="
ls -lh "$VENDOR/lib/libopencore-amrnb.a"
lipo -info "$VENDOR/lib/libopencore-amrnb.a"
