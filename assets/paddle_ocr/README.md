# PaddleOCR assets (Phase 3 — multilingual OCR)

This directory is populated **out of band** with the four artifacts
that `PaddleOcrEngine.kt` unpacks on first activation:

| Filename | Source | Size | Purpose |
|---|---|---|---|
| `det.nb` | PaddleOCR PP-OCRv4 mobile det | ~5 MB | Text-line detection |
| `rec_multilingual.nb` | PaddleOCR PP-OCRv4 multilingual rec | ~10 MB | CTC-decoded recognition (Latin + Cyrillic + Kazakh) |
| `cls.nb` | PaddleOCR cls | ~1 MB | 0°/180° text-line classifier |
| `keys.txt` | PaddleOCR multilingual charset | <1 KB | Charset incl. Ә Ғ Қ Ң Ө Ұ Ү Һ І |
| `kk_wordlist.txt.gz` | kk-Wikipedia frequency list, gzipped | ~2 MB | Loaded by `KkDictionary` for post-correction |

Until the artifacts above are committed:

- `PaddleOcrEngine.probe()` returns
  `available = false, unavailableReason = "models_missing"`.
- `OcrService` falls back to the legacy ML Kit pipeline for every
  language (works for Latin/English, breaks for Cyrillic — same as
  the Phase 0 status quo).
- `KkDictionary.load()` returns `false`, post-correction becomes a
  no-op.

## How to produce the artifacts

### 1. Models

Pull the PP-OCRv4 mobile multilingual artifacts from the
[PaddleOCR releases](https://github.com/PaddlePaddle/PaddleOCR/releases).
Convert each one to PaddleLite NB format using `opt_tool`:

```bash
./opt \
  --model_file=ch_PP-OCRv4_det_infer.pdmodel \
  --param_file=ch_PP-OCRv4_det_infer.pdiparams \
  --optimize_out=det \
  --valid_targets=arm
# repeat for cls and rec_multilingual
```

Drop `det.nb`, `rec_multilingual.nb`, `cls.nb`, and the charset's
`keys.txt` into this directory.

### 2. PaddleLite runtime

Download the matching version of `PaddleLite.aar` and place it at
`android/app/libs/PaddleLite.aar`. Reference it from
`android/app/build.gradle.kts`:

```kotlin
dependencies {
    implementation(files("libs/PaddleLite.aar"))
}
```

### 3. Kazakh wordlist

Produce `kk_wordlist.txt.gz` from a frequency list (kk-Wikipedia is
the recommended source per
`plans/bagdar-kazakh-language-stack-1f2668.md`):

```bash
# UTF-8, one word per line, lowercased.
sort -u kk_words.txt | gzip -9 -c > kk_wordlist.txt.gz
```

Aim for the top ~100 000 entries — that gives the post-correction
step enough coverage to fix Cyrillic/Kazakh confusions on real-world
signage and documents without bloating the APK.

### 4. Sanity test

After committing the artifacts:

```bash
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

Then in the app: enable `enableKazakhStackV2` in dev settings, switch
language to Kazakh, point the camera at a kk-language sign. Expected:
recognized text appears with the Kazakh extra letters intact and the
field log emits a `paddle_ocr_session` event with a non-zero
`lines_returned`.

## License

The PaddleOCR models and PaddleLite runtime are Apache-2.0 licensed.
Bundling them in the APK is compatible with Bagdar's offline-first
distribution. See `plans/bagdar-kazakh-language-stack-1f2668.md`
"Decisions" table for the locked-in choice of PaddleLite over ONNX
Runtime.
