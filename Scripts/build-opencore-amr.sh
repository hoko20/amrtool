#!/usr/bin/env bash
# 构建三个 iOS device(arm64) 静态库到 Vendor/：
#   libopencore-amrnb.a  AMR-NB
#   libvo-amrwbenc.a     AMR-WB
#   libSKP_SILK_SDK.a    SILK v3
# 头文件：Vendor/include/interf_enc.h、enc_if.h、silk/*.h
set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/audioforge-deps"
MIN_IOS="${MIN_IOS:-16.0}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：构建 iOS 静态库需要 macOS + Xcode（当前系统：$(uname -s)）。" >&2
    exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK" "$VENDOR/lib" "$VENDOR/include/silk"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
ARCH_FLAGS="-target arm64-apple-ios$MIN_IOS -arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN_IOS -O2 -fPIC"

# 编译器包装：无论 Makefile 如何拼变量，都强制 iOS 目标
mkdir -p "$WORK/toolchain"
cat > "$WORK/toolchain/clang-ios" <<EOF
#!/bin/bash
exec "$CC" -target arm64-apple-ios$MIN_IOS -isysroot "$SDK" -miphoneos-version-min=$MIN_IOS "\$@"
EOF
chmod +x "$WORK/toolchain/clang-ios"
IOS_CC="$WORK/toolchain/clang-ios"

check_ios_archive() {
    local info
    info="$(otool -l "$1" 2>/dev/null)"
    # otool 对 LC_BUILD_VERSION 输出数字：1=macOS，2=iOS
    if [[ -z "$info" ]] \
       || ! grep -Eq "platform (IOS|2)|LC_VERSION_MIN_IPHONEOS" <<<"$info" \
       || grep -Eq "platform (MACOS|1)" <<<"$info"; then
        echo "错误：$1 不是纯 iOS 目标编译产物" >&2
        grep -E "platform |LC_VERSION_MIN" <<<"$info" | sort -u | head -5 >&2
        exit 1
    fi
}

echo "== 环境 =="
echo "SDK: $SDK"
echo "MIN_IOS: $MIN_IOS"
"$CC" --version | head -1

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
    echo "opencore-amr 源码不完整：$NB_SRC" >&2
    exit 1
fi

(
    cd "$NB_SRC"
    ./configure --host=aarch64-apple-darwin \
                --disable-shared --enable-static --enable-compile-c \
                --disable-dependency-tracking \
                CC="$IOS_CC" CXX="$IOS_CC"
    make -j"$(sysctl -n hw.ncpu)" -C amrnb \
         CC="$IOS_CC" CXX="$IOS_CC" \
         CFLAGS="$ARCH_FLAGS" CXXFLAGS="$ARCH_FLAGS" LDFLAGS="$ARCH_FLAGS"
)
cp "$NB_SRC/amrnb/.libs/libopencore-amrnb.a" "$VENDOR/lib/libopencore-amrnb.a"
cp "$NB_SRC/amrnb/interf_enc.h" "$VENDOR/include/interf_enc.h"

# ---------------------------------------------------------------- AMR-WB
WB_VER="0.1.3"
echo "== AMR-WB: vo-amrwbenc ${WB_VER} =="
WB_TAR="$WORK/vo-amrwbenc.tar.gz"
curl -fsSL --retry 5 --retry-delay 3 -o "$WB_TAR" \
    "https://downloads.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-${WB_VER}.tar.gz"
tar xzf "$WB_TAR" -C "$WORK"
WB_SRC="$WORK/vo-amrwbenc-${WB_VER}"
mkdir -p "$WORK/wbobj"

# 直接手编：configure 会给 arm64 加上 -DARM -DARMV7 -DASM_OPT，触发 32 位汇编分支
for source in "$WB_SRC/wrapper.c" "$WB_SRC/common/cmnMemory.c" "$WB_SRC"/amrwbenc/src/*.c; do
    "$CC" -c $ARCH_FLAGS \
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
if [ ! -d "$SILK_SRC/src" ]; then
    echo "silk 源码目录缺失：$SILK_SRC" >&2
    exit 1
fi
mkdir -p "$WORK/silkobj"
for source in "$SILK_SRC"/src/*.c; do
    "$CC" -c $ARCH_FLAGS \
        -I"$SILK_SRC/interface" \
        -I"$SILK_SRC/src" \
        "$source" -o "$WORK/silkobj/$(basename "${source%.c}").o"
done
ar rcs "$VENDOR/lib/libSKP_SILK_SDK.a" "$WORK"/silkobj/*.o
cp "$SILK_SRC"/interface/*.h "$VENDOR/include/silk/"

# ---------------------------------------------------------------- 校验
echo "== 产物校验 =="
for lib in libopencore-amrnb libvo-amrwbenc libSKP_SILK_SDK; do
    lipo -info "$VENDOR/lib/$lib.a"
    check_ios_archive "$VENDOR/lib/$lib.a"
done
nm -gU "$VENDOR/lib/libopencore-amrnb.a" | grep -c "Encoder_Interface_Encode"
nm -gU "$VENDOR/lib/libvo-amrwbenc.a" | grep -c "E_IF_encode"
nm -gU "$VENDOR/lib/libSKP_SILK_SDK.a" | grep -c "SKP_Silk_SDK_Encode"
ls -lh "$VENDOR/lib"
