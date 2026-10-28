# Bagdar Core Safety RC — validation report

Date: 2026-09-12  
**Authorization for supervised assistive use: no.**  
Generic obstacles remain `shadow`. `kGenericObstacleAssistiveAuthorized`
is false.

## Software evidence (this tree)

| Gate | Result |
| --- | --- |
| Core vs research compile-time policy | pass (software) |
| README / minSdk / asset claims | pass (documentation) |
| dart analyze | pass (0 issues after Phase 2) |
| flutter test --no-pub (ordinary) | pass except 1 named skip for missing NCNN corpus |
| RC mode missing NCNN corpus | fail as required (`BAGDAR_RC=true`) |
| Core debug APK | pass (`build/app/outputs/flutter-apk/app-core-debug.apk`, 558,869,521 bytes, SHA-256 `a99dd4d043b64347a39395bbe0c1276775fd4042d51b9fb8f28ebcc824de37fe`) |
| Health coordinator truth table | pass (unit) |
| Misalignment software contract | pass (unit) |
| SOS delivery machine (composer ≠ sent) | pass (unit) |
| Map package verify/rollback contract | pass (unit, no city data) |

## Blocked (not simulated)

| Gate | Why |
| --- | --- |
| NCNN vs reference ρ ≥ 0.90 | `reference_outputs.json` absent |
| Native/Dart NCNN pixel parity | no device |
| ARCore single-owner spike | no device; see camera-decision doc |
| Device-matrix FPS / thermal / 30 min | no named devices |
| Controlled walking Stages A–E | not started |
| TalkBack / Scanner / Switch Access | no device walkthrough |
| Real SMS sentIntent/delivery on hardware | no authorized send |
| Pilot-city OSM package | not selected / not packaged |
| Release signing / final applicationId | no authority |
| Play SMS / FGS declarations | prepared in docs only |
| Generic `assistive` | validation report does not authorize a build |

A unit-test pass or a debug APK is not Core Safety RC completion.
