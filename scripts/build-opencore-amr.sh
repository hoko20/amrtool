#!/usr/bin/env bash
# 构建三个 iOS device(arm64) 静态库：
#   1. opencore-amr  -> AMR-NB  (libopencore-amrnb.a)
#   2. vo-amrwbenc   -> AMR-WB  (libvo-amrwbenc.a)
#   3. silk-v3       -> SILK    (libSKP_SILK_SDK.a)
# 产物目录：Vendor/lib、Vendor/include
set -euo pipefail

# macOS 自带 bash 3.2 在非 UTF-8 locale 下会把中文标点误并进变量名
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/amr-deps-build"
MIN_IOS="${MIN_IOS:-26.0}"

rm -rf "$WORK"
mkdir -p "$WORK" "$VENDOR/lib" "$VENDOR/include" "$VENDOR/include/silk"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"
CLANGXX="$(dirname "$CLANG")/clang++"
ARCH_FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=${MIN_IOS}"

echo "== 环境 =="
echo "SDK: $SDK"
"$CLANG" --version | head -1

# ---------------------------------------------------------------- AMR-NB
NB_VER="0.1.6"
echo "== AMR-NB: opencore-amr ${NB_VER} =="
NB_TAR="$WORK/opencore-amr.tar.gz"
if curl -fsSL --retry 5 --retry-delay 3 -o "$NB_TAR" \
    "https://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-${NB_VER}.tar.gz"; then
  tar xzf "$NB_TAR" -C "$WORK"
  NB_SRC="$WORK/opencore-amr-${NB_VER}"
else
  echo "SourceForge 下载失败，改用 GitHub 镜像"
  git clone --depth 1 https://github.com/feuvan/opencore-amr-iOS "$WORK/nb-mirror"
  NB_SRC="$(find "$WORK/nb-mirror" -maxdepth 3 -type f -name configure -exec dirname {} \; | head -1)"
fi

if [ ! -f "$NB_SRC/configure" ]; then
  echo "opencore-amr 源码不完整：$NB_SRC"
  ls -la "$NB_SRC" || true
  exit 1
fi

cd "$NB_SRC"
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
make -j"$(sysctl -n hw.ncpu)" -C amrnb
cp amrnb/.libs/libopencore-amrnb.a "$VENDOR/lib/libopencore-amrnb.a"
cp amrnb/interf_enc.h "$VENDOR/include/interf_enc.h"

# ---------------------------------------------------------------- AMR-WB
WB_VER="0.1.3"
echo "== AMR-WB: vo-amrwbenc ${WB_VER} =="
WB_TAR="$WORK/vo-amrwbenc.tar.gz"
curl -fsSL --retry 5 --retry-delay 3 -o "$WB_TAR" \
  "https://downloads.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-${WB_VER}.tar.gz"
tar xzf "$WB_TAR" -C "$WORK"
WB_SRC="$WORK/vo-amrwbenc-${WB_VER}"
mkdir -p "$WORK/wbobj"

# 直接手编：configure 会给 arm64 加上 -DARM -DARMV7 -DASM_OPT，导致 32 位汇编分支报错
for source in "$WB_SRC/wrapper.c" "$WB_SRC"/amrwbenc/src/*.c; do
  "$CLANG" -c $ARCH_FLAGS -O2 -fPIC \
    -I"$WB_SRC/amrwbenc/inc" \
    -I"$WB_SRC/common/include" \
    "$source" -o "$WORK/wbobj/$(basename "${source%.c}").o"
done
ar rcs "$VENDOR/lib/libvo-amrwbenc.a" "$WORK"/wbobj/*.o
cp "$WB_SRC/enc_if.h" "$VENDOR/include/enc_if.h"

# ---------------------------------------------------------------- SILK
echo "== SILK: silk-v3-decoder =="
SILK_REPO="$WORK/silk-v3"
git clone --depth 1 https://github.com/kn007/silk-v3-decoder "$SILK_REPO"
SILK_SRC="$SILK_REPO/silk"
mkdir -p "$WORK/silkobj"

if [ ! -d "$SILK_SRC/src" ]; then
  echo "silk 源码目录缺失：$SILK_SRC"
  exit 1
fi

for source in "$SILK_SRC"/src/*.c; do
  "$CLANG" -c $ARCH_FLAGS -O2 -fPIC \
    -I"$SILK_SRC/interface" \
    -I"$SILK_SRC/src" \
    "$source" -o "$WORK/silkobj/$(basename "${source%.c}").o"
done
ar rcs "$VENDOR/lib/libSKP_SILK_SDK.a" "$WORK"/silkobj/*.o
cp "$SILK_SRC"/interface/*.h "$VENDOR/include/silk/"

# ---------------------------------------------------------------- 校验
echo "== 产物校验 =="
ls -lh "$VENDOR/lib"
for lib in libopencore-amrnb libvo-amrwbenc libSKP_SILK_SDK; do
  lipo -info "$VENDOR/lib/$lib.a"
done

nm -gU "$VENDOR/lib/libopencore-amrnb.a" | grep -c "Encoder_Interface_Encode"
nm -gU "$VENDOR/lib/libvo-amrwbenc.a" | grep -c "E_IF_encode"
nm -gU "$VENDOR/lib/libSKP_SILK_SDK.a" | grep -c "SKP_Silk_SDK_Encode"
ls "$VENDOR/include" "$VENDOR/include/silk"
