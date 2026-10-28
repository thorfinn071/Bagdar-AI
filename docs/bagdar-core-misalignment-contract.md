# Misalignment product contract (software)

Date: 2026-09-12  
Owner phases: Phase 2 (green tests against this contract), Phase 7 (named-device
and onboarding). Device walkthroughs remain **blocked**.

This contract replaces ad-hoc H6 expectations that conflicted with audit D-5.
Tests must follow this document, not the previous output of either the old
watchdog or the epoch-default no-detection bug.

Bagdar must never treat a mis-aimed or covered camera as an operational
empty scene. It also must not call a quiet street “clear”.

---

## States (phone pose)

| State | Meaning | Watchdog episode? |
| --- | --- | --- |
| optimal pitch | camera can observe the walking corridor | no |
| too high / too low / flat | corridor not in view | yes, if moving |
| excessive roll | handled by orientation TTS; not this watchdog | no |
| covered / pocket | `FrameQualityGuard.cameraBlocked` (separate path) | no |
| unstable motion | blur / stall watchdogs | no |

Moving = `walking` **or** `running`. Stationary never starts an episode.

---

## Episode

An episode is active when **all** of:

1. pitch is not optimal;
2. user is walking or running;
3. no YOLO/track detection in the last `kDetectionFreshness` (5 s), **or**
   no detection has been recorded in this session.

Clocks use injected `now`, not callback counts.

Reset (clear sustained timer, haptic timer, verbal flags, no-detection
reannounce) when any of: pitch returns to optimal, motion becomes
stationary, a detection arrives, a new camera session starts (host calls
`reset()`).

---

## Haptic

After `kWarningThreshold` (10 s) of a continuous episode, fire a tactile
pattern every `kHapticInterval` (15 s), **independent of depth health**.

Nothing haptic before 10 s.

---

## Verbal — depth-blind path

Depth is “blind” when status is `lowConfidence`, `planeFitFailed`,
`unalignedStale`, `providerUnavailable`, or `legacyOnlyDegraded` for at
least `kLowConfidenceConfirmation` (15 s).

Then:

- at 10 s sustained: one warning per episode, key `pitch_misaligned_blind`;
- at 35 s: critical, same key, re-announce every `kCriticalReannounce` (60 s).

This path is used when the pipeline has actually reported blindness.

---

## Verbal — no-detection fallback (D-5)

If depth is **not** confirmed blind (healthy empty scene **or** a silent
stuck-`ok` depth failure), the user still needs a warning when the camera
has been off-corridor with no objects for a long time.

Measure “no detection” as:

- `now - lastDetection` when a detection was seen this session;
- otherwise the **episode duration** (`now - sustainedSince`).

Never use Unix epoch or an uninitialized timestamp.

Then, only if the depth-blind path did not already produce speech on this
tick:

- after `kNoDetectionThreshold` (20 s): warning, key `misalign_no_detections`;
- re-announce every `kNoDetectionReannounce` (60 s);
- do **not** fire this fallback while `isDepthBlindAt` is true (the
  depth-blind key is the authority in that case).

Before 20 s of no-detection time: no D-5 speech.

Empty scene (depth `ok`) therefore: haptic from 10 s; verbal only from 20 s
with `misalign_no_detections`; never `pitch_misaligned_blind`.

---

## What this is not

- Not a “path clear” or “no obstacles” announcement.
- Not a substitute for covered-camera / stall / permission failures.
- Named-device walking, pocket, and one-handed tests: Phase 7 / 12, blocked
  without a phone.
