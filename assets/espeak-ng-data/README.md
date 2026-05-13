# espeak-ng voice data (Phase 2 — Kazakh language stack)

This directory is populated by `tools/espeak-ng/build_android.sh` from a
pinned upstream commit of [espeak-ng/espeak-ng](https://github.com/espeak-ng/espeak-ng)
using NDK r25c. See `tools/espeak-ng/README.md` for the full
reproducible-build recipe.

Until the build has been run at least once:

- This directory contains only this README.
- `EspeakNgEngine.probe()` reports `available = false` with reason
  `voice_data_missing`.
- `TtsService._resolveKkEngine()` skips espeak and falls through to the
  Russian voice fallback. This is the intended behavior; no functional
  regression is introduced by shipping without the data.

After the build completes, the layout looks like:

```
assets/espeak-ng-data/
  kk_dict             # Kazakh phoneme dictionary
  ru_dict             # Russian phoneme dictionary
  en_dict             # English phoneme dictionary
  intonations         # Common intonation tables
  phondata            # Compiled phoneme data
  phonindex           # Phoneme index
  phontab             # Phoneme table
  voices/             # Voice metadata files
```

These files are read from `context.filesDir/espeak-ng-data/` after
`EspeakNgEngine` unpacks them on first activation. Total bundle size:
~10 MB.

Do **not** check in voice data manually — use the build script so the
output stays reproducible and hash-verifiable against
`tools/espeak-ng/verify_build.sh`.
