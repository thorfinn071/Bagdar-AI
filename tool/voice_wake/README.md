# Local wake candidate — research only

This slice evaluates the isolated name **Бағдар / Багдар** using the official
`vosk-model-small-kz-0.42` (Apache 2.0). The vocabulary contains `бағдар` (id
161401) and `[unk]` (id 199962). This establishes vocabulary availability, not
recognition quality. The current candidate **failed** the synthetic development
fixture and is not connected to command execution.

## Reproduce on Windows

From the repository root (PowerShell):

```powershell
python -m venv output/voice-wake/venv
& output/voice-wake/venv/Scripts/python.exe -m pip install vosk==0.3.45 psutil==7.2.2
Invoke-WebRequest https://alphacephei.com/vosk/models/vosk-model-small-kz-0.42.zip -OutFile output/voice-wake/model.zip
python tool/voice_wake/prepare_model.py --archive output/voice-wake/model.zip
& tool/voice_wake/generate_synthetic_corpus.ps1 -OutputDirectory output/voice-wake/corpus
& output/voice-wake/venv/Scripts/python.exe tool/voice_wake/evaluate.py --model android/app/src/research/assets/voice_wake --corpus output/voice-wake/corpus --mode grammar-only --output output/voice-wake/grammar.json
& output/voice-wake/venv/Scripts/python.exe tool/voice_wake/evaluate.py --model android/app/src/research/assets/voice_wake --corpus output/voice-wake/corpus --mode verified --output output/voice-wake/verified.json
```

The generator requires the installed SAPI voices Microsoft Irina and Microsoft
Pavel. It creates 72 mono PCM16 16kHz clips: 12 positive and 60 deliberately
difficult negative examples. Both voices speak Russian; reading the spelling
`Бағдар` through SAPI does not create Kazakh human evidence. The same fixture was
used to develop the verifier: this is **not a holdout**. A rate per hour computed
from these short, selected negatives is not a real-world operating rate.

The archive is pinned by SHA-256. Installation refuses mismatched archives and
different existing model files. There are 14 files / 106,987,412 uncompressed
bytes. Runtime verifies their hashes before loading from app-private,
non-backed-up storage. No runtime model download occurs.

## Research microphone audition

```powershell
flutter build apk --flavor research --debug --no-pub --dart-define=BAGDAR_RESEARCH=true --dart-define=BAGDAR_WAKE_PROBE=true
```

The accessible test control appears only with both Dart defines in Research.
Native Core independently rejects wake input, and Core contains no wake model.
The test requires explicit activation and microphone permission, plays a
non-speech readiness cue, stops after five minutes or ten detected utterances,
and counts detections. A detection **cannot** run a command, change a setting,
send SOS, or create onboarding readiness. User stop, background, other speech,
audio interruption and noisy-route events invalidate the test; returning to the
foreground does not restart it. An unconfirmed native stop blocks microphone
handoff. Existing emergency output and countdown deadlines do not await it.

Inference runs on one native worker. Grammar endpoint candidates must be the
single exact word, have a finite score >= .85 and a duration .25–2 seconds. A
second full-vocabulary recognizer verifies the last four seconds of volatile
PCM. Partial text cannot activate the probe. The score threshold is a
provisional rejection rule, not a calibrated probability. Audio/transcripts
are not stored by the app; the explicit desktop corpus tool stores its own
synthetic test files. No command ASR or cloud fallback is invoked by the probe.

Desktop Vosk is 0.3.45; Android uses the existing 0.3.47 runtime. Android parity,
capture teardown, network behavior, RSS/peak memory, battery, heat, TalkBack,
audio routing, and human RU/KK/EN pronunciation remain `not_run`.

Before automatic activation, select/train a candidate that retains positives
while rejecting hard negatives, freeze its policy, evaluate independent human
audio and measure a named 6–8GB Android. `policy.json` records provisional
targets, and every report keeps `promotionAllowed=false` regardless of desktop
results. Onboarding wake support and pause/resume are later integration work.

Sources: [official models and licenses](https://alphacephei.com/vosk/models),
[Android deployment](https://alphacephei.com/vosk/android),
[Vosk recognizer](https://github.com/alphacep/vosk-api/blob/master/src/recognizer.cc).
