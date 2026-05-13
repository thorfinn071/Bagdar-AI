#!/usr/bin/env bash
# Reproducible espeak-ng Android build for Bagdar Phase 2.
#
# See `tools/espeak-ng/README.md` for the full recipe. Run from any
# directory; the script chdir's to its own location.
#
# Output:
#   ../../android/app/src/main/jniLibs/arm64-v8a/libbagdar-espeakng.so
#   ../../android/app/src/main/jniLibs/armeabi-v7a/libbagdar-espeakng.so
#   ../../assets/espeak-ng-data/*
#
# Environment:
#   ANDROID_NDK_HOME  path to NDK r25c (required)
#   ESPEAKNG_GIT_URL  upstream remote (defaults to GitHub mirror)
#   ESPEAKNG_GIT_REV  pinned commit SHA (required for reproducibility)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Pinned upstream commit. Bump intentionally; CI will reject mismatched
# hashes via verify_build.sh.
: "${ESPEAKNG_GIT_URL:=https://github.com/espeak-ng/espeak-ng.git}"
: "${ESPEAKNG_GIT_REV:=8be1cdd3866db4280e9bd3a0d6e69c64dcf90e8e}"  # 2024-02-15 master
: "${MIN_SDK_VERSION:=26}"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ANDROID_NDK_HOME must point to NDK r25c" >&2
    exit 1
fi
if [[ ! -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" ]]; then
    echo "ANDROID_NDK_HOME is not a valid NDK install: $ANDROID_NDK_HOME" >&2
    exit 1
fi

BUILD_DIR="$SCRIPT_DIR/build"
SRC_DIR="$BUILD_DIR/espeak-ng"
INSTALL_DIR="$BUILD_DIR/install"
JNI_LIBS_DIR="$REPO_ROOT/android/app/src/main/jniLibs"
ASSETS_DIR="$REPO_ROOT/assets/espeak-ng-data"

mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$ASSETS_DIR"

# Detect the NDK host tag (linux-x86_64, darwin-x86_64, windows-x86_64).
HOST_TAG=""
for candidate in linux-x86_64 darwin-x86_64 darwin-arm64 windows-x86_64; do
    if [[ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$candidate" ]]; then
        HOST_TAG="$candidate"
        break
    fi
done
if [[ -z "$HOST_TAG" ]]; then
    echo "Could not find LLVM toolchain in $ANDROID_NDK_HOME" >&2
    exit 1
fi
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"

clone_or_update() {
    if [[ -d "$SRC_DIR/.git" ]]; then
        git -C "$SRC_DIR" fetch --depth=1 origin "$ESPEAKNG_GIT_REV"
        git -C "$SRC_DIR" checkout -f "$ESPEAKNG_GIT_REV"
        git -C "$SRC_DIR" clean -fdx
    else
        rm -rf "$SRC_DIR"
        git clone "$ESPEAKNG_GIT_URL" "$SRC_DIR"
        git -C "$SRC_DIR" checkout -f "$ESPEAKNG_GIT_REV"
    fi
}

# espeak-ng's bootstrap requires autotools.
require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required tool missing: $1" >&2
        exit 1
    fi
}
require_tool git
require_tool autoconf
require_tool automake
require_tool libtool
require_tool make

build_abi() {
    local abi="$1"
    local triple="$2"
    local llvm_target="$3"

    local prefix="$INSTALL_DIR/$abi"
    local build_subdir="$BUILD_DIR/abi-$abi"
    rm -rf "$build_subdir"
    mkdir -p "$build_subdir"

    pushd "$SRC_DIR" >/dev/null
    if [[ ! -f configure ]]; then
        ./autogen.sh
    fi
    popd >/dev/null

    pushd "$build_subdir" >/dev/null
    local cc="$TOOLCHAIN/bin/${llvm_target}${MIN_SDK_VERSION}-clang"
    local ar="$TOOLCHAIN/bin/llvm-ar"
    local ranlib="$TOOLCHAIN/bin/llvm-ranlib"
    local strip="$TOOLCHAIN/bin/llvm-strip"

    CC="$cc" AR="$ar" RANLIB="$ranlib" STRIP="$strip" \
        CFLAGS="-O2 -fPIC -DANDROID -DNDEBUG" \
        LDFLAGS="-Wl,--no-undefined" \
        "$SRC_DIR/configure" \
            --host="$triple" \
            --prefix="$prefix" \
            --disable-static \
            --enable-shared \
            --with-pic \
            --without-async \
            --without-pcaudiolib \
            --without-klatt \
            --without-mbrola \
            --without-sonic

    make -j"$(getconf _NPROCESSORS_ONLN || echo 4)"
    make install

    # Rename to avoid colliding with any system-installed espeak-ng.
    if [[ -f "$prefix/lib/libespeak-ng.so" ]]; then
        cp -f "$prefix/lib/libespeak-ng.so" \
            "$prefix/lib/libbagdar-espeakng.so"
        "$strip" --strip-unneeded "$prefix/lib/libbagdar-espeakng.so"
    fi

    mkdir -p "$JNI_LIBS_DIR/$abi"
    if [[ -f "$prefix/lib/libbagdar-espeakng.so" ]]; then
        cp -f "$prefix/lib/libbagdar-espeakng.so" \
            "$JNI_LIBS_DIR/$abi/libbagdar-espeakng.so"
    fi
    popd >/dev/null
}

stage_voice_data() {
    local data_src="$INSTALL_DIR/arm64-v8a/share/espeak-ng-data"
    if [[ ! -d "$data_src" ]]; then
        echo "espeak-ng-data not produced at $data_src" >&2
        return 1
    fi
    # Wipe stale data; keep the README in place.
    find "$ASSETS_DIR" -mindepth 1 -maxdepth 1 ! -name 'README.md' \
        -exec rm -rf {} +
    cp -R "$data_src/." "$ASSETS_DIR/"
}

main() {
    echo "==> Cloning espeak-ng @ $ESPEAKNG_GIT_REV"
    clone_or_update

    echo "==> Building arm64-v8a"
    build_abi arm64-v8a aarch64-linux-android aarch64-linux-android

    echo "==> Building armeabi-v7a"
    build_abi armeabi-v7a arm-linux-androideabi armv7a-linux-androideabi

    echo "==> Staging voice data into assets/espeak-ng-data/"
    stage_voice_data

    if [[ ! -f "$SCRIPT_DIR/jni/bagdar_espeakng.c" ]]; then
        cat >&2 <<'EOF'
==> NOTE: tools/espeak-ng/jni/bagdar_espeakng.c is not yet present.
    espeak-ng itself was built and staged, but the Bagdar JNI shim that
    exposes `nativeInit / nativeVersion / nativeSynth` to Kotlin has not
    been written yet. EspeakNgEngine.probe() will keep returning
    `available = false` until the shim is added and rebuilt.
    See tools/espeak-ng/README.md for the symbol contract.
EOF
    fi

    echo "==> Done."
    echo "    Verify the output with: ./verify_build.sh"
}

main "$@"
