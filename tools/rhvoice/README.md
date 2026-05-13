# RHVoice `kk-aigul` pack — Bagdar Phase 2

This directory documents the build + upload procedure for the
downloadable RHVoice Kazakh voice pack consumed by
`@android/app/src/main/kotlin/com/example/bagdar/RhvoiceEngine.kt`.

Unlike espeak-ng, RHVoice is **not** bundled in the APK — the pack is
~30 MB, ships out-of-band via GitHub Releases, and is installed on
demand by `LanguagePackManager`. The Bagdar onboarding flow surfaces a
tap-to-confirm modal for it; the language packs settings screen lets
users install/delete/update it later.

## Upstream

| Field | Value |
|---|---|
| Engine | [RHVoice/RHVoice](https://github.com/RHVoice/RHVoice) |
| Voice | `kk-aigul` (CC-BY-3.0, distributed in the upstream voice repo) |
| Engine license | LGPL-2.1+ (dynamic-link only — locked in by `plans/bagdar-kazakh-language-stack-1f2668.md`) |
| Voice license | CC-BY-3.0 — attribution required in app's About screen |

Custom-commissioned Kazakh voice work is explicitly **out of scope**
for Phase 2 and tracked in the roadmap section of the plan.

## Pack layout

`RhvoiceEngine.kt` expects this exact directory structure inside the
extracted pack (`<packsDir>/rhvoice-kk-aigul/`):

```
rhvoice-kk-aigul/
  lib/
    arm64-v8a/librhvoice.so          # required (loaded via System.load)
    armeabi-v7a/librhvoice.so        # required for 32-bit devices
  voice/
    aigul/                           # required (RHVoice voice + dict files)
      voice.params
      pitch.fst
      ...
  LICENSE.txt                        # required — refusing to load without it
  VERSION.txt                        # optional — surfaced via getInstalled()
```

The engine refuses to activate if any of these are missing or if
`LICENSE.txt` is absent — see `RhvoiceEngine.probe()`. Both `lib/<abi>/`
and `voice/` paths are anchored at the pack root; **do not** nest the
zip with an extra wrapping directory.

## Build & upload checklist

This is a **reference checklist**, not an automated script — RHVoice's
Android port involves significant tooling that lives upstream. The
build host requires Linux + NDK r25c + RHVoice's documented Android
recipe (see [RHVoice Android docs](https://github.com/RHVoice/RHVoice/blob/master/doc/en/Android.md)).

1. **Build `librhvoice.so` for both ABIs** following the upstream
   Android instructions. Pin to a specific RHVoice commit so the build
   stays reproducible.

2. **Pull the `aigul` voice data** from
   [RHVoice/RHVoice-language-data](https://github.com/RHVoice/RHVoice-language-data)
   (path: `kazakh/aigul/`). Drop the entire directory under
   `rhvoice-kk-aigul/voice/aigul/`.

3. **Compose `LICENSE.txt`** — concatenate, in this order:
   - RHVoice engine LGPL-2.1 notice
   - aigul CC-BY-3.0 notice with the upstream creator attribution
   - A pointer back to the Bagdar repo

4. **Write `VERSION.txt`** with a single line like `1.0` matching the
   manifest's `version` field.

5. **Zip the directory** with deterministic flags so re-runs produce
   byte-identical archives:

   ```bash
   cd rhvoice-kk-aigul
   find . -type f | sort | TZ=UTC \
       xargs zip -X -D ../rhvoice-kk-aigul-1.0.zip
   ```

   The `-X` flag strips extra file attributes; `-D` skips directory
   entries; `TZ=UTC` + the `find | sort` pipeline ensures the entries
   are inserted in a stable order with stable timestamps.

6. **Compute SHA-256** for the manifest:

   ```bash
   sha256sum rhvoice-kk-aigul-1.0.zip
   ```

7. **Upload as a release asset** under the existing `lang-packs-v1`
   GitHub Release on `thorfinn071/Bagdar-AI`. Use the asset URL the
   manifest expects:

   ```
   https://github.com/thorfinn071/Bagdar-AI/releases/download/lang-packs-v1/rhvoice-kk-aigul-1.0.zip
   ```

8. **Update the manifest** at the `lang-packs-manifest` release tag.
   Add (or update) the `rhvoice-kk-aigul` entry:

   ```json
   {
     "id": "rhvoice-kk-aigul",
     "version": "1.0",
     "url": "https://github.com/thorfinn071/Bagdar-AI/releases/download/lang-packs-v1/rhvoice-kk-aigul-1.0.zip",
     "size": <bytes>,
     "sha256": "<sha256 from step 6>",
     "minAppVersion": "1.2.0",
     "name": "RHVoice (Айгүл)",
     "nameKk": "RHVoice (Айгүл)",
     "nameEn": "RHVoice (Aigul)"
   }
   ```

9. **Smoke test on-device**:
   - Fresh install → onboarding accepts the kk pack → RHVoice modal
     appears → tap Download → progress UI updates → install completes
     within a 30-minute window on a cellular connection.
   - After install, `RhvoiceEngine.probe()` returns
     `available = true` and `TtsService.activeKkEngine ==
     KkTtsEngine.rhvoice`.
   - Critical-priority alert during ongoing kk speech preempts within
     100 ms (measured via the existing `TtsService` stall timer).
   - LICENSE attribution is rendered in the app's About screen.

10. **Tag and release** — bump the app's `version` in `pubspec.yaml` if
    the pack needs a `minAppVersion` higher than what's currently
    shipped, then cut the next app release.

## Why no `build_android.sh` here

RHVoice's Android build is upstream-maintained and the toolchain
shifts faster than espeak-ng's. Bagdar deliberately keeps a documented
checklist instead of pinning a build script so we don't fork the
upstream Android port. When upstream's Android build stabilizes, this
README can be replaced with a `build_android.sh` mirror of the
espeak-ng pipeline.

## Disabling RHVoice without uninstalling the pack

If a user reports voice issues and you need to force the resolver to
skip RHVoice without deleting the pack:

1. Open Language Packs settings.
2. Toggle off `enableKazakhStackV2` — the resolver will downgrade kk
   to the Russian fallback even if both packs are installed.

Re-enabling the toggle restores RHVoice on the next kk speech.
