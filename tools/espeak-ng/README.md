# espeak-ng reproducible Android build — Bagdar Phase 2

This directory contains everything needed to produce the espeak-ng
artifacts that Phase 2 of the Kazakh language stack
(`plans/bagdar-kazakh-language-stack-1f2668.md`) ships in the APK:

| Artifact | Path in repo | Purpose |
|---|---|---|
| `libbagdar-espeakng.so` (arm64-v8a) | `android/app/src/main/jniLibs/arm64-v8a/` | espeak-ng 1.51 native synthesizer |
| `libbagdar-espeakng.so` (armeabi-v7a) | `android/app/src/main/jniLibs/armeabi-v7a/` | 32-bit variant |
| Voice data | `assets/espeak-ng-data/` | kk + ru + en phoneme tables |

The build is **reproducible**: given the same NDK version and pinned
upstream commit, the output bytes are byte-identical. CI verifies this
via `verify_build.sh`.

## Prerequisites

- Linux or macOS host (Windows: use WSL2)
- Android NDK r25c (`ndk-bundle/25.2.9519653/`). Newer NDKs will work but
  break reproducibility; do not upgrade casually.
- `autoconf`, `automake`, `libtool`, `make`, `git`
- ~500 MB of free disk for the upstream checkout + objects

## One-shot build

```bash
cd tools/espeak-ng
export ANDROID_NDK_HOME=/path/to/android-ndk-r25c
./build_android.sh
./verify_build.sh   # hashes outputs against the pinned manifest
```

After a successful build, commit the new `.so` files and `assets/espeak-ng-data/`
contents — they are deliberately checked in so downstream contributors
can build the APK without the NDK installed.

## Pinned upstream commit

`espeak-ng/espeak-ng` is pinned in `build_android.sh` via `ESPEAKNG_GIT_REV`.
To bump the upstream version:

1. Update `ESPEAKNG_GIT_REV` to the new commit SHA.
2. Re-run `build_android.sh` on the reference host.
3. Re-run `verify_build.sh` to regenerate `expected_hashes.txt`.
4. Verify on a Snapdragon 680-class device that:
   - The bundled kk voice still loads (`EspeakNgEngine.activate()` returns
     `true`).
   - Pronunciation of the six acceptance phrases listed in the plan
     (greeting, hazard, navigation cue, SOS countdown, OCR text,
     command confirmation) is unchanged or improved.

## Output layout

```
build/
  espeak-ng/                    # upstream checkout
  install/
    arm64-v8a/
      lib/libespeak-ng.a        # static archive, linked into the .so
      include/espeak-ng/        # headers for the JNI shim
    armeabi-v7a/
      lib/libespeak-ng.a
    share/espeak-ng-data/       # → copied to assets/espeak-ng-data/
```

The script then compiles `jni/bagdar_espeakng.c` and statically links
it with `libespeak-ng.a` to produce one
`libbagdar-espeakng.so` per ABI inside
`android/app/src/main/jniLibs/`. The custom name + symbol visibility
hidden (`-fvisibility=hidden`, only the three JNI exports are public)
guarantees no collision with any other espeak-ng port the device might
have installed system-wide.

## JNI surface

`EspeakNgEngine.kt` expects the following symbols to be exported by
`libbagdar-espeakng.so`. They are implemented by
`jni/bagdar_espeakng.c` and linked into the .so by `build_android.sh`:

- `Java_com_example_bagdar_EspeakNgEngine_nativeInit(JNIEnv*, jobject, jstring dataPath)` → `jint`
  - Returns 0 on success, -1 on init failure. Idempotent.
- `Java_com_example_bagdar_EspeakNgEngine_nativeVersion(JNIEnv*, jobject)` → `jstring`
  - Returns the espeak-ng version string from `espeak_Info()`.
- `Java_com_example_bagdar_EspeakNgEngine_nativeSynth(JNIEnv*, jobject, jstring text, jstring lang, jint wpm)` → `jbyteArray?`
  - Returns 16-bit signed little-endian mono PCM at 22050 Hz, or `null`
    on synth failure / OOM.

The C wrapper serializes calls behind a single mutex (espeak-ng's API
is not re-entrant) and caches the last voice + rate so repeated
utterances skip the per-call voice-load overhead (~15 ms on Snapdragon
680).

If `jni/bagdar_espeakng.c` is missing, `build_android.sh` skips the
final link step, `EspeakNgEngine.probe()` reports `available = false`,
and the Dart resolver falls back to the Russian voice — no
functional regression.
