# Bagdar KWS CNN experiment v1

Next data-collection slice: [human pilot instructions](HUMAN_COLLECTION.md).
`human_collection.py` preregisters train/dev/test participants, imports selected
sessions, audits coverage, and keeps test out of development exports. It uses
only the Python standard library. No human recordings have been collected yet;
the original trainer still belongs to the failed synthetic protocol below.

A small, **failed** offline candidate; it does not replace the application's
Vosk research probe and cannot run commands. The checkpoint has 54,897
parameters; the frozen float32 TFLite file is 275,544 bytes. It classifies one
segmented utterance, not a continuous microphone stream.

## Reproduce (Windows, Python 3.11)

```powershell
python -m venv output/kws-cnn/venv
& output/kws-cnn/venv/Scripts/python.exe -m pip install -r tool/voice_wake/neural/requirements.txt
& output/kws-cnn/venv/Scripts/python.exe tool/voice_wake/neural/download.py --output output/kws-cnn/data
& tool/voice_wake/neural/generate_sapi_test.ps1 -OutputDirectory output/kws-cnn/corpus
& output/kws-cnn/venv/Scripts/python.exe tool/voice_wake/neural/corpus.py --data output/kws-cnn/data --output output/kws-cnn/corpus
& output/kws-cnn/venv/Scripts/python.exe tool/voice_wake/neural/train.py --manifest output/kws-cnn/corpus/manifest.json --output output/kws-cnn/candidate
& output/kws-cnn/venv/Scripts/python.exe tool/voice_wake/neural/evaluate.py --manifest output/kws-cnn/corpus/manifest.json --candidate output/kws-cnn/candidate --output output/kws-cnn/holdout.json
& output/kws-cnn/venv/Scripts/python.exe -m unittest discover -s tool/voice_wake/neural -p test_pipeline.py -v
```

SAPI requires Microsoft Irina, Microsoft Pavel and Microsoft Zira Desktop.
The recorded run reused already-installed TensorFlow/Numpy via a local venv
with `--system-site-packages`; the dependency versions above are pinned.
Piper's voice models and FSDD are downloaded **only for offline tooling**.
Neither voice models nor this candidate are added to the APK. Preserve the
generated corpus and its SHA-256 manifest: this exact corpus, rather than a
promise of bit-identical TTS regeneration on other runtimes, binds the run.

## Split and freeze

`protocol.json` was fixed before synthesis/training. `sources.json` pins the
Piper repository revision and model checksums, and the FSDD commit. Each WAV
has a SHA-256, origin, language and speaker group. The auditor rejects speaker
or audio duplicates across train/dev/test, altered audio and escaped paths.

The 3,669 source clips contain 2,288 train, 608 dev and 773 test clips.
Train and dev are the only audio loaded by training. Train augmentation has
4,096 examples with retained parent ids/seeds. Speaker groups are held apart
for the classifier; the TTS generators and upstream datasets can share
lineage, and this does not create independent human positive evidence.

All 33 test positives are synthetic. The 740 test negatives include 500
human English digit clips from a held-out FSDD speaker. FSDD is not Russian/
Kazakh conversation, traffic, music, silence, or whole-phone usage. SAPI test
speakers also appeared in the earlier Vosk diagnostic, but are absent from
this CNN's train/dev data. The test phrases/labels were fixed in advance;
this is not a blinded external evaluation.

Threshold selection uses only dev and the predefined grid. No grid value
met zero false positive utterances and >=90% recall in each language. Thus
`selectionFeasible=false` and the predefined diagnostic threshold .9 is used.
The model and policy were frozen before test evaluation. They must not be
retuned on this now-inspected holdout. Another candidate needs a new protocol
and fresh held-out data. The tool refuses to retrain a frozen destination.

## Signal/export contract

Input: mono PCM16 at 16kHz. Python energy segmentation rejects empty,
non-finite, silent, clipped or >1.8-second speech spans, normalizes RMS and
centers the utterance in 32,000 samples. Rejected positives remain misses.
This energy rule is not proof of speech, microphone health or keyword identity.

TFLite consumes the resulting canonical float32 waveform `[1,32000]` and
contains STFT (400/160/512), 40 log-mel bands, normalization and the CNN.
Output `[1,1]` is a model score, not calibrated confidence. Native input
segmentation/RMS/padding and whole Android parity are not implemented.
There are no Flex/custom/resource-variable ops. The initial export retained
uninitialized variables and was rejected by parity; learned checkpoint
weights were unchanged, then explicitly frozen into constants. Maximum score
error on 608 dev cases is `5.275e-6`, with zero decision disagreements.

If conversion fails, keep the checkpoint and use `train.py --resume-export`.
This does not fit weights again or use test data. The original trainer hash
and final exporter hash are retained separately. The frozen model hashes and
parity report are in the candidate directory.

## Result and evidence boundary

At frozen threshold .9: 6/33 positive utterances found, 27/33 missed, 27/740
negative utterances incorrectly positive. These counts fail the fixture.
The desktop TFLite invocation is milliseconds, but excludes capture,
segmentation, audio focus, ASR and Android. Hours derived from selected clips
are not continuous false-wake rates. A zero count on short audio cannot
establish the 0.5/hour target; the report includes its statistical upper bound.
`evidenceSufficientForTargets=false` and `promotionAllowed=false` are retained
even when an imported human batch has better observed counts.

## Explicit human import for a later, independent evaluation

Copy `human_manifest.template.json`, use anonymous speaker ids, confirm each
label by listening, and record participant consent before marking it true.
Supply actual SHA-256 values (`Get-FileHash -Algorithm SHA256`). Import only
selected single-utterance WAVs, mono PCM16/16kHz, at most eight seconds. The
tool never starts a microphone, uploads speech or overwrites a frozen corpus.

```powershell
& output/kws-cnn/venv/Scripts/python.exe tool/voice_wake/neural/import_human.py --manifest C:/recordings/manifest.json --recording-root C:/recordings --expected-capture-id capture-001 --output output/kws-human-001
& output/kws-cnn/venv/Scripts/python.exe tool/voice_wake/neural/evaluate.py --manifest output/kws-cnn/corpus/manifest.json --candidate output/kws-cnn/candidate --external-human-manifest output/kws-human-001/manifest.json --output output/kws-human-001/report.json
```

Matching a selected capture id/hash means selection consistency; consent,
speaker identity, capture origin and label correctness remain supplier
assertions, not authenticated sensor evidence. The template is deliberately
unconfirmed. Tests use generated fixture WAVs, not actual human participants.
No human positive collection was run in this stage. Collect natural RU/KK/EN
pronunciations, near words, negations and context phrases across different
speakers/devices. Keep all variants of a speaker in one split and reserve
unseen speakers for final testing. Continuous-stream and named Android
acceptance remain separate work after a useful candidate exists.

## Source attribution

- Piper: [OHF-Voice implementation](https://github.com/OHF-Voice/piper1-gpl).
  Its generator is GPL-3.0; it is an offline dependency, not application code.
- Voice weights/cards: [piper-voices](https://huggingface.co/rhasspy/piper-voices).
  Dmitri/Denis/Joe cards name CC0; LJSpeech names public domain; Kazakh ISSAI
  cards name CC-BY-4.0 and credit [IS2AI Kazakh TTS](https://github.com/IS2AI/Kazakh_TTS).
  The downloaded source cards are retained. Model lineage is described there.
- FSDD: [Jakobovski/free-spoken-digit-dataset](https://github.com/Jakobovski/free-spoken-digit-dataset),
  CC-BY-SA-4.0. Only its English spoken digits are used, all as negatives.
