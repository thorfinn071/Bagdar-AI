#!/usr/bin/env bash
# Reproducibility check for the espeak-ng Android build.
#
# Hashes every artifact produced by build_android.sh and compares to the
# pinned manifest. Used by CI to ensure that committing a bumped
# ESPEAKNG_GIT_REV always produces identical output regardless of which
# contributor ran the build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPECTED="$SCRIPT_DIR/expected_hashes.txt"

JNI_LIBS_DIR="$REPO_ROOT/android/app/src/main/jniLibs"
ASSETS_DIR="$REPO_ROOT/assets/espeak-ng-data"

if ! command -v sha256sum >/dev/null 2>&1; then
    # macOS ships `shasum` instead.
    sha() { shasum -a 256 "$@"; }
else
    sha() { sha256sum "$@"; }
fi

ACTUAL_TMP="$(mktemp)"
trap 'rm -f "$ACTUAL_TMP"' EXIT

declare -a TARGETS=()
[[ -f "$JNI_LIBS_DIR/arm64-v8a/libbagdar-espeakng.so" ]] && \
    TARGETS+=("$JNI_LIBS_DIR/arm64-v8a/libbagdar-espeakng.so")
[[ -f "$JNI_LIBS_DIR/armeabi-v7a/libbagdar-espeakng.so" ]] && \
    TARGETS+=("$JNI_LIBS_DIR/armeabi-v7a/libbagdar-espeakng.so")

# Voice data — hash every regular file (except this README).
while IFS= read -r -d '' file; do
    TARGETS+=("$file")
done < <(find "$ASSETS_DIR" -type f ! -name 'README.md' -print0)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "verify_build: nothing to verify yet (run build_android.sh first)" >&2
    exit 0
fi

for target in "${TARGETS[@]}"; do
    rel="${target#"$REPO_ROOT/"}"
    line="$(sha "$target" | awk '{print $1}')  $rel"
    echo "$line" >> "$ACTUAL_TMP"
done
sort -k2 "$ACTUAL_TMP" -o "$ACTUAL_TMP"

if [[ ! -f "$EXPECTED" ]]; then
    echo "verify_build: no expected_hashes.txt found — recording baseline"
    cp "$ACTUAL_TMP" "$EXPECTED"
    echo "  -> wrote $(wc -l < "$EXPECTED") hashes to $EXPECTED"
    exit 0
fi

if diff -u "$EXPECTED" "$ACTUAL_TMP"; then
    echo "verify_build: OK"
else
    echo "verify_build: MISMATCH" >&2
    echo "Either the upstream commit / NDK toolchain has changed, or" >&2
    echo "the build is not reproducible. Re-run with the pinned versions" >&2
    echo "in build_android.sh, or update expected_hashes.txt intentionally." >&2
    exit 1
fi
