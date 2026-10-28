# Bagdar Android request correlation

Source: flutter_tts 4.2.5, copied from the resolved pub package. LICENSE retained.
Only lib/flutter_tts.dart and the Android FlutterTtsPlugin.kt are patched.
Other platform implementations are unchanged.

`speakWithRequestId` calls `bagdarSpeak` on Android. The supplied ID travels
through TextToSpeech's utteranceId and a separate `bagdar.speechEvent` callback.
Legacy callbacks remain available to upstream callers. Bagdar ignores them
when using correlated playback. Tagged requests reject an unready engine
instead of entering upstream's deferred/retry queue, which could speak after
the caller has timed out. IDs must be unique for the process lifetime.

Pub cache is never edited. Upgrade by comparing this small patch with upstream.
Android compilation confirms API wiring, not audible output or device timing.
