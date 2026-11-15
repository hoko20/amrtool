#!/usr/bin/env bash
# 用 opencore-amr 自带的 autotools 构建 iOS device 静态库（AMR-NB 编解码，C 模式）。
# 产物：Vendor/lib/libopencore-amrnb.a、Vendor/include/interf_enc.h
#
# 注意：opencore-amr 0.1.6 的 amrnb/ 目录只有头文件和 wrapper.cpp，
# 编码器实现位于 opencore/codecs_v2/audio/gsm_amr/ 下，必须走 configure + make。
set -euo pipefail

# macOS 自带 bash 3.2 在非 UTF-8 locale 下会把中文标点误并进变量名，这里强制 UTF-8。
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/opencore-amr-build"
VERSION="0.1.6"
MIN_IOS="${MIN_IOS:-26.0}"

rm -rf "$WORK"
mkdir -p "$WORK" "$VENDOR/lib" "$VENDOR/include"

SRC="$WORK/opencore-amr-$VERSION"

echo "== 获取 opencore-amr $VERSION =="
if curl -fsSL --retry 5 --retry-delay 3 \
    -o "$WORK/src.tar.gz" \
    "https://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-$VERSION.tar.gz"; then
  tar xzf "$WORK/src.tar.gz" -C "$WORK"
else
  echo "SourceForge 下载失败，改用 GitHub 镜像"
  git clone --depth 1 https://github.com/feuvan/opencore-amr-iOS "$WORK/mirror"
  SRC="$(find "$WORK/mirror" -maxdepth 3 -type f -name configure -exec dirname {} \; | head -1)"
  [ -n "$SRC" ] || SRC="$WORK/mirror"
fi

if [ ! -f "$SRC/configure" ]; then
  echo "源码里没有 configure，目录结构："
  ls -la "$SRC" || true
  exit 1
fi
echo "源码目录：$SRC"

echo "== 配置交叉编译（arm64 / iOS ${MIN_IOS}）=="
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"
CLANGXX="$(dirname "$CLANG")/clang++"
ARCH_FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN_IOS"

cd "$SRC"
./configure \
  --host=arm-apple-darwin \
  --disable-shared \
  --enable-static \
  --enable-compile-c \
  --disable-dependency-tracking \
  CC="$CLANG" \
  CXX="$CLANGXX" \
  CFLAGS="$ARCH_FLAGS -O2 -fPIC" \
  CXXFLAGS="$ARCH_FLAGS -O2 -fPIC" \
  LDFLAGS="$ARCH_FLAGS"

echo "== 编译 libopencore-amrnb =="
make -j"$(sysctl -n hw.ncpu)" -C amrnb

echo "== 安装到 Vendor =="
cp amrnb/.libs/libopencore-amrnb.a "$VENDOR/lib/libopencore-amrnb.a"
cp amrnb/interf_enc.h "$VENDOR/include/interf_enc.h"

ls -lh "$VENDOR/lib/libopencore-amrnb.a"
lipo -info "$VENDOR/lib/libopencore-amrnb.a"
nm -gU "$VENDOR/lib/libopencore-amrnb.a" | grep -c "Encoder_Interface_Encode" || true
