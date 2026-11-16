#!/usr/bin/env bash
#
# 构建 AMR-NB / AMR-WB / SILK 三套 arm64 静态库到 Vendor/
# 仅在 macOS + Xcode 环境执行（本地或 GitHub Actions）。
#

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：该脚本需要 macOS + Xcode（当前系统：$(uname -s)）。" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="$ROOT/build/vendor-src"
MIN_IOS="16.0"
ARCH="arm64"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
COMMON_FLAGS="-target arm64-apple-ios$MIN_IOS -arch $ARCH -isysroot $SDK -miphoneos-version-min=$MIN_IOS -O2 -fPIC"

mkdir -p "$VENDOR/lib" "$VENDOR/include/silk" "$WORK"

if [[ -f "$VENDOR/lib/libopencore-amrnb.a" && \
      -f "$VENDOR/lib/libvo-amrwbenc.a" && \
      -f "$VENDOR/lib/libSKP_SILK_SDK.a" && \
      -f "$VENDOR/include/interf_enc.h" && \
      -f "$VENDOR/include/enc_if.h" && \
      -f "$VENDOR/include/silk/SKP_Silk_SDK_API.h" ]]; then
  echo "==> Vendor 静态库已存在，跳过构建"
  exit 0
fi

fetch() {
  local url="$1" out="$2"
  if [[ ! -f "$out" ]]; then
    echo "==> 下载 $(basename "$out")"
    curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
  fi
}

# ---------- opencore-amr（AMR-NB 编码） ----------

fetch "https://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz" \
      "$WORK/opencore-amr.tar.gz"
rm -rf "$WORK/opencore-amr-0.1.6"
tar -xzf "$WORK/opencore-amr.tar.gz" -C "$WORK"
cd "$WORK/opencore-amr-0.1.6"
./configure --host=aarch64-apple-darwin \
            --disable-shared --enable-static \
            --prefix="$WORK/prefix-opencore" \
            CC="$CC" CFLAGS="$COMMON_FLAGS" LDFLAGS="$COMMON_FLAGS"
make -j"$(sysctl -n hw.ncpu)"
make install
cp "$WORK/prefix-opencore/lib/libopencore-amrnb.a" "$VENDOR/lib/"
NB_HEADER="$(find "$WORK/prefix-opencore" -name 'interf_enc.h' | head -1)"
if [[ -z "$NB_HEADER" ]]; then
  echo "找不到 interf_enc.h" >&2
  exit 1
fi
cp "$NB_HEADER" "$VENDOR/include/"

# ---------- vo-amrwbenc（AMR-WB 编码） ----------

fetch "https://downloads.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz" \
      "$WORK/vo-amrwbenc.tar.gz"
rm -rf "$WORK/vo-amrwbenc-0.1.3"
tar -xzf "$WORK/vo-amrwbenc.tar.gz" -C "$WORK"
cd "$WORK/vo-amrwbenc-0.1.3"
./configure --host=aarch64-apple-darwin \
            --disable-shared --enable-static \
            --prefix="$WORK/prefix-amrwbenc" \
            CC="$CC" CFLAGS="$COMMON_FLAGS" LDFLAGS="$COMMON_FLAGS"
make -j"$(sysctl -n hw.ncpu)"
make install
cp "$WORK/prefix-amrwbenc/lib/libvo-amrwbenc.a" "$VENDOR/lib/"
WB_HEADER="$(find "$WORK/prefix-amrwbenc" -name 'enc_if.h' | head -1)"
if [[ -z "$WB_HEADER" ]]; then
  echo "找不到 enc_if.h" >&2
  exit 1
fi
cp "$WB_HEADER" "$VENDOR/include/"

# ---------- silk-v3-decoder（SILK 编码） ----------

fetch "https://github.com/kn007/silk-v3-decoder/archive/refs/heads/master.tar.gz" \
      "$WORK/silk.tar.gz"
rm -rf "$WORK"/silk-v3-decoder-*
tar -xzf "$WORK/silk.tar.gz" -C "$WORK"
SILK_DIR="$(find "$WORK" -maxdepth 1 -type d -name 'silk-v3-decoder-*' | head -1)"
if [[ -z "$SILK_DIR" ]]; then
  echo "找不到 silk-v3-decoder 源码目录" >&2
  exit 1
fi

SILK_SRC="$SILK_DIR/silk/src"
[[ -d "$SILK_SRC" ]] || SILK_SRC="$SILK_DIR/src"

SILK_HEADER="$(find "$SILK_DIR" -name 'SKP_Silk_SDK_API.h' | head -1)"
if [[ -z "$SILK_HEADER" ]]; then
  echo "找不到 SKP_Silk_SDK_API.h" >&2
  exit 1
fi
SILK_INCLUDE="$(dirname "$SILK_HEADER")"

OBJ="$WORK/silk-obj"
rm -rf "$OBJ"
mkdir -p "$OBJ"

echo "==> 编译 SILK 源码"
while IFS= read -r -d '' file; do
  "$CC" $COMMON_FLAGS -I"$SILK_SRC" -I"$SILK_INCLUDE" \
        -c "$file" -o "$OBJ/$(basename "${file%.c}").o"
done < <(find "$SILK_SRC" -name '*.c' -print0)

libtool -static -o "$VENDOR/lib/libSKP_SILK_SDK.a" "$OBJ"/*.o

# 头文件全部拷贝，避免 SDK 内部 include 缺失
cp "$SILK_INCLUDE"/*.h "$VENDOR/include/silk/"
if [[ "$SILK_INCLUDE" != "$SILK_SRC" ]]; then
  cp "$SILK_SRC"/*.h "$VENDOR/include/silk/" 2>/dev/null || true
fi

echo "==> Vendor 构建完成"
ls -l "$VENDOR/lib"
