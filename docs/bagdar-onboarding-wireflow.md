# Bagdar onboarding v2 — selected direction and wireflow

2026-09-30. The user selected **option 2 of revision 02**,
`docs/design/onboarding/2026-09-30/revision-02/02-language-form.png`.
The earlier four-screen boards were rejected. This file records the implementation
contract before changing application code.

## Returning users and recovery — 2026-10-01

When required training modules are complete, entry opens a three-part session
check: confirmed signals, camera permission, and camera/temperature/alignment.
Permission status is read without a prompt. Speech, camera and sensors start only
from explicit controls. Device checking requires a fresh confirmed signal and
the user's stationary confirmation; successful sensors still require human
alignment confirmation. The existing SessionGate remains authoritative and
admits stationary inspection only. Backgrounding invalidates all live evidence.
Setup and training remain available from this page.

Practice stores only completed examples, after a correct answer and explicit
Next. Returning to practice resumes the first unfinished example. Restart and
language change reset exercise progress. The optional v2 JSON field
`completedExercises` accepts integers 0–4 and preserves older records without it.
Wrong answers explain the specific cue, including lost sensing and pause/resume.

Speech failures distinguish language voice, engine, interruption, timeout and
playback errors. Retry repeats the same sample or instruction; reading an
instruction never verifies a feedback channel. Android speech settings are an
explicit recovery action with an accessibility-settings fallback. Neither a
successful platform call nor a saved training record proves physical audibility.

## Visual contract

Native Flutter UI, Inter, warm off-white background, graphite text and primary
button, one white grouped form with thin separators. No illustrations, hero
icons, gradients or marketing carousel. 24 logical-pixel side margins, 74-pixel
language rows, 60-pixel minimum primary button. The language page reproduces the
selected layout; subsequent pages use the same form language.

At 390 × 844 the language heading starts near y=145, the grouped form near y=275
and the primary action near y=626. At 200% text or in landscape, the page scrolls
and controls grow vertically. No fixed text heights or hidden overflow.

## Flow and copy contract

All copy lives in one typed RU/KK/EN content catalog. Each page has a main semantic
heading; information blocks have additional short headings. Focus order is header, heading, explanation, form, secondary actions,
primary action, footer. Navigation never starts speech automatically: TalkBack
owns ordinary reading. Explicit “Listen” actions use the existing TTS service.
Each transition stops speech and haptics, then saves a versioned local checkpoint
before changing the page. A failed write leaves the user on the same page.

The semantic heading includes the current step and total. Interactive signal and
status rows expose button roles and one semantic action. The summary names the
next missing requirement; it and Continue setup use the same admission rules,
including human alignment confirmation. On resume, permission status is re-read
without starting a stream; stale device/channel evidence remains invalidated.
Exercise transitions are serialized and cancelled transitions cannot advance.
Every step offers explicit instruction replay and speech stop. Instruction
playback includes mandatory copy and current failures, does not grant module or
channel completion, and uses sequential short utterances through the existing TTS.
Live-region announcements are suppressed while app speech is active. Semantic
locale follows the selected language; language choices expose their own locales.
Exercises expose a localized sequence heading and keyboard focus on transition.
Alignment keeps the runtime angular limits and gives a specific correction after
an explicit probe; stale/malformed/sparse data and missing user confirmation block
admission. The rolling stable window is covered by deterministic tests, not yet
by named-device evidence. Optional voice guidance runs at most four explicit
measure/hint cycles, through the same TTS queue, while the user stays stationary.
It opens no camera and never confirms alignment for the user. Stop, background,
sensor/voice timeout and late results invalidate the guided position result.
Guidance retry measures again before giving advice.

Helper mode has a session-local handoff. The helper may configure settings and
run probes, but personal acknowledgements, exercise answers and inspection are
blocked until control is explicitly handed to the user. Handoff clears signal
examples and personal confirmations; saved training remains. A new launch in
helper mode requires a fresh handoff. This records an explicit workflow action,
not the identity of the person operating the phone.

Limits and privacy use short semantic headings, visible mandatory warnings,
explicit playback per block and optional expanded explanations. Reading or
expanding a block never supplies consent or marks training complete.
See [accessibility next steps](bagdar-onboarding-accessibility-next-steps.md) for
the remaining speech, focus and independent setup work and its device gates.

| Module | User task / completion | Failure and recovery |
| --- | --- | --- |
| Language | Choose Қазақша / Русский / English; optional example; continue in selected language | Unavailable voice is shown; selection still works visually. Language changes invalidate signal verification and training. |
| Access | Choose voice, large text with voice, or helper; explicitly hand control to the user | Helper cannot supply personal confirmations or exercise answers. Handoff requires replaying signals. |
| Limits | Read four titled limitations or replay each block, then explicitly acknowledge | Mandatory warnings stay visible; additional explanations are optional. No timer or automatic advance. |
| Feedback | Play ordinary voice, critical stop voice, stop vibration; confirm only signals actually heard/felt | Technical playback is separate from human confirmation. Without a verified critical channel only training is available. |
| Privacy | Explain existing local frame processing, no recording in this flow, optional diagnostics off | No microphone, location, SMS, contacts, analytics or network requests in the new flow. |
| Vocabulary | Read/replay stop, side obstacle, unavailable, pause/resume | Text remains usable when audio is unavailable. |
| Practice | Deterministic stop, side obstacle, loss of camera, pause/resume; correct explicit actions | Camera-free and no external effects. Wrong action shows correction and does not complete the exercise. Replay and exit are always available. |
| Camera | Explain camera use, then request **camera only**, or continue without camera | Denied/restricted/permanent denial stays unavailable; settings and retry available; training remains available. |
| Device | Explicitly probe permission, fresh changing frames and thermal state | Timeout, frozen/dark/covered or unsupported stream is unavailable, never “clear”. Probe closes camera. |
| Alignment | Teach stationary hold/mount; manual stable sensor check or explicitly selected voice guidance, then personal confirmation | Guidance has at most four measured attempts, serial hints and an always available Stop action. Missing/unsteady sensor data cannot be confirmed as verified. This does not set optical calibration or metres. |
| Stationary | Remain still in a familiar place; repeat fresh camera check | No walking instructions or obstacle-accuracy claims. |
| Summary | Separate setup, user-verified signals, training, camera, alignment, temperature, feature availability | Targeted recheck buttons. Restart/resume never reuses persisted device readiness. |

“Continue later” saves the current checkpoint and opens the local readiness
summary. Back changes only the visible checkpoint; it does not erase completed
modules. Closing/reopening resumes the checkpoint. Old `onboarding_done` is not
accepted as v2 evidence and is not overwritten. Future/corrupt storage fails
closed with an explicit recovery choice; future data is preserved.

## Admission and rollout

As of 2026-10-01, v2 is the only application entry, on every launch. The legacy
screen and `BAGDAR_ONBOARDING_V2` switch have been removed at the user's request.
The summary is always the entry before an explicit camera session. Training is always local.
A camera inspection may open only after required setup/training and fresh current
permission/frame/alignment/channel checks. This is a stationary inspection scope,
not independent mobility. `kGenericObstacleAssistiveAuthorized` remains false.
The camera runtime retains its own authoritative Core health and alert arbiter;
onboarding probe results are disposable setup evidence, not a competing runtime
health coordinator. No overall “safe to walk” status is emitted.

Users without v2 state begin the new setup even if an old `onboarding_done`
value exists. Saved v2 checkpoints resume normally. Corrupt or future v2 state
opens the existing recovery path. Old completion and mode preferences are ignored;
camera inspection explicitly starts in scan mode. There is no route back to legacy onboarding.

The preview entry point uses the same production widgets with explicit in-memory
storage and unavailable hardware adapters. It never fabricates readiness.

## Acceptance

Desktop checks: persistence failure, corrupt/future data, resume, language
invalidation, unavailable/expired evidence, camera-denial training, required
practice actions, no unauthorized assistive admission, 200%/landscape layout,
semantic controls and real Flutter screenshot comparison against selected image.

Android camera/TTS/haptics/sensors, TalkBack/Switch Access, interrupted audio,
background/revocation and target-user sessions remain manual release gates.
Widget tests and screenshots cannot establish those gates.
