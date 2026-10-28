# Accessibility report (software preparation)

Current source/software audit and prioritized plan (2026-10-11): [independent-use audit](bagdar-independent-use-audit-2026-10-11.md), [improvement plan](bagdar-independent-use-improvement-plan-2026-10-11.md). The manual device checks below remain unexecuted; component semantics tests do not establish accessibility of the composed camera screen.

Date: 2026-09-12  
Status: **blocked** for manual TalkBack, Scanner, Switch Access, and Samsung
Voice Assistant. Automated semantics tests exist for QuickShelf and
StepperField.

## Manual TalkBack checklist (not executed)

Do not mark pass without a real device walkthrough.

1. Cold start → onboarding language, purpose, phone position, permissions,
   emergency contact, alert demo, capability check. Each step has a
   reachable control (not gesture-only).
2. Camera session: start/stop, status panel (`core_health_status`), repeat
   last important message.
3. Permission denial and regrant.
4. SOS control and fall-cancel (deliberate, not single accidental tap).
5. Settings: speech rate, language, contact. No deferred experiment
   toggles on Core.
6. Headphones / Bluetooth route change and incoming call.
7. 48 dp targets, large text, no color-only state.
8. TalkBack + app TTS do not make Core actions unusable.

## Automated

- `test/quick_shelf_test.dart` — selected state, 64 dp height
- `test/stepper_field_test.dart` — button semantics
- Status panel exposes `core_health_status`

## Not run

Android Accessibility Scanner, TalkBack linear navigation, Switch Access,
Samsung variant, moderated user testing.
