# Alert arbitration policy

Date: 2026-09-12  
Owner: `AlertManager` + `AlertFilter`. Detectors must not call TTS.

## Lanes (high to low)

1. Emergency countdown / SOS instruction
2. Imminent collision or drop
3. System unavailable / degraded
4. Ordinary obstacle or navigation turn
5. Informational / on-demand speech

Fall countdown speech is not permanently evicted by repeating stairs
warnings. A new critical track is not hidden by another track’s cooldown.

Critical same-category opposite pans may both speak
(`alert_filter_same_category_critical_test.dart`).

Haptic floor applies to `kHapticCriticalAlertPattern` and any call with
`isCritical: true`. Relative depth never speaks metres.

Concurrency software tests: alert filter same-category, fall countdown
preemption, TTS stall haptic fallback. Device call-interruption and
blindfold distinction: **blocked**.
