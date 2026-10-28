# SOS and fall delivery contract

Date: 2026-09-12

UI update, 2026-10-11: [accessible SOS implementation and evidence](bagdar-sos-accessibility-2026-10-11.md). Countdown cancellation still requires two deliberate actions within three seconds. Manual requests and countdown escalation share one in-flight attempt; a manual escalation is not announced as cancellation. Screen-reader device acceptance remains unexecuted.

## Delivery meanings

| Phase | User meaning |
| --- | --- |
| acceptedByModem | radio stack accepted the SMS |
| delivered | delivery receipt received |
| deliveryUnconfirmed | accepted or queued; no receipt |
| composerOpened | SMS app opened; user must send |
| dialerOpened | dialer opened; user must call |
| failed / rejected / timedOut | not sent |

Opening `sms:` or `tel:` is never “SOS sent”.

`SosDeliveryMachine` is the software state machine. Native `sentIntent`
exists; delivery receipts and dual-SIM selection are still incomplete.
No real SMS is sent by tests.

## Fall

Windows are duration-based where already converted. Gyro-missing uses a
degraded Class A path. Single tap must not cancel (see
`fall_countdown_cancel_test.dart`). Device fall-mat and lock-screen:
**blocked**.
