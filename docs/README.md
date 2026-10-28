# Bagdar documentation

Run commands and resolve inline source paths from the repository root unless
specified otherwise. Reports retain their original dates and evidence scope.
A passing replay or emulator run does not establish physical-device readiness.

## Current entry points

- [Repository map and cleanup record](repository-structure.md)
- [Contribution and verification conventions](../CONTRIBUTING.md)
- [Research dataset provisioning and publication status](../tool/datasets/README.md)
- [Core scope](bagdar-core-scope.md) and [Core verifier](../tool/verify_core.md)
- [Quality and continuity: executed evaluation, 2026-10-27](quality-and-continuity-evaluation-2026-10-27.md)
- [Quality and continuity: implementation plan and remaining milestones](quality-and-continuity-implementation-plan-2026-10-27.md)
- [Simulation lab: batch results, 2026-10-27](simulation-lab-continuation-2026-10-27.md)
- [Stationary physical-device acceptance checklist](stationary-device-acceptance-checklist-2026-10-27.md)
- [Onboarding wireflow](bagdar-onboarding-wireflow.md)
- [Inspection observations and uncertainty](inspection-evidence-status-2026-10-19.md)

## Catalogue

The catalogue lists every Markdown document directly under `docs/`. Related
protocols and evaluations stay at their existing paths so frozen receipts and
source references remain stable. A plan describes intended work; an evaluation
records what was actually measured.

### Core scope, safety and spatial contracts

- [Accessibility report (software preparation)](bagdar-core-accessibility-report.md)
- [Alert arbitration policy](bagdar-core-alert-policy.md)
- [Bagdar Core — Phase 0 baseline (evidence freeze)](bagdar-core-baseline.md)
- [Device matrix](bagdar-core-device-matrix.md)
- [Bagdar Core — сфокусированный план до надёжного первого релиза](bagdar-core-focused-execution-plan.md)
- [Bagdar Core — master implementation and validation plan](bagdar-core-hardening-master-plan.md)
- [Core health contract](bagdar-core-health-contract.md)
- [Misalignment product contract (software)](bagdar-core-misalignment-contract.md)
- [Bagdar Core — scope and permission matrix](bagdar-core-scope.md)
- [SOS and fall delivery contract](bagdar-core-sos-contract.md)
- [Bagdar Core Safety RC — validation report](bagdar-core-validation-report.md)
- [Bagdar Spatial Safety — план реализации восприятия, обхода препятствий и предупреждений](bagdar-spatial-safety-implementation-plan.md)
- [Bagdar Spatial Safety — план завершения работ](bagdar-spatial-safety-remaining-work-plan.md)
- [Generic obstacle stack — Phase 0 baseline](generic-obstacle-baseline.md)
- [Camera-ownership decision (Phase 6 gate)](generic-obstacle-camera-decision.md)
- [Bagdar Core: implementation plan for generic obstacle detection](generic-obstacle-stack-implementation-plan.md)
- [Generic obstacle validation report](generic-obstacle-validation-report.md)
- [Copy-paste execution prompt for Grok 4.6 Extra High](grok-bagdar-core-execution-prompt.md)
- [Контракт метрического подтверждения прохода](passage-clearance-contract-2026-10-02.md)
- [Промты для ИИ — фиксы проблем safety-аудита (июнь 2026)](safety-audit-2026-06-prompts.md)
- [Safety-аудит Bagdar — июнь 2026](safety-audit-2026-06.md)
- [Bagdar Spatial Safety — replay corpus contract](spatial-corpus-contract.md)
- [Spatial recording import v2 — paired-frame admission](spatial-recording-import-v2.md)
- [Bagdar Spatial Safety — Runtime Integration Report](spatial-runtime-integration-report.md)
- [Bagdar Spatial Safety — validation report](spatial-safety-validation-report.md)

### Onboarding, accessibility, voice and interface

- [Единый интерфейс Bagdar AI](bagdar-design-system.md)
- [Bagdar AI: аудит самостоятельного использования незрячим пользователем](bagdar-independent-use-audit-2026-10-11.md)
- [Bagdar AI: план улучшения самостоятельного использования](bagdar-independent-use-improvement-plan-2026-10-11.md)
- [Основной экран: доступные команды осмотра](bagdar-inspection-accessibility-2026-10-11.md)
- [Onboarding v2: самостоятельное прохождение незрячим пользователем](bagdar-onboarding-accessibility-next-steps.md)
- [Bagdar AI Onboarding — мастер-план реализации](bagdar-onboarding-implementation-plan.md)
- [Bagdar AI: короткие задания и восстановление первого запуска](bagdar-onboarding-recovery-2026-10-12.md)
- [Bagdar AI: первый запуск и обучение](bagdar-onboarding-ux-2026-10-11.md)
- [Bagdar onboarding v2 — selected direction and wireflow](bagdar-onboarding-wireflow.md)
- [SOS: первый этап доступного самостоятельного сценария](bagdar-sos-accessibility-2026-10-11.md)
- [Bagdar: протокол проверки самостоятельного использования на Android](bagdar-talkback-acceptance-2026-10-12.md)
- [Bagdar AI: управление голосом и звуковой onboarding](bagdar-voice-first-interface.md)
- [Bagdar AI: первый срез голосового onboarding](bagdar-voice-onboarding-stage1-2026-10-13.md)
- [Bagdar AI: голосовые разрешения и проверки устройства](bagdar-voice-onboarding-stage2-2026-10-13.md)
- [Bagdar: голосовые команды неподвижного осмотра — третий срез](bagdar-voice-runtime-stage3-2026-10-13.md)
- [Bagdar: голосовые настройки речи и оформления — четвёртый срез](bagdar-voice-settings-stage4-2026-10-13.md)
- [Bagdar: локальное обращение, первый исследовательский срез](bagdar-voice-wake-stage5-2026-10-13.md)
- [Bagdar: обучаемый кандидат обращения и проверка на отложенных голосах](bagdar-voice-wake-stage6-2026-10-14.md)
- [Bagdar: подготовка человеческого набора для следующего кандидата](bagdar-voice-wake-stage7-2026-10-14.md)
- [Camera observations and walking clearance — 19 October 2026](inspection-evidence-status-2026-10-19.md)

### Image quality, simulation and continuity

- [Bagdar: проверка пар качества в Android-приложении](image-quality-android-probe-2026-10-27.md)
- [Bagdar: независимая проверка фильтра резкости](image-quality-evaluation-2026-10-27.md)
- [Независимая проверка фильтра качества Bagdar](image-quality-protocol-2026-10-27.md)
- [Image quality and simulation continuity evaluation](quality-and-continuity-evaluation-2026-10-27.md)
- [Quality observer and simulation continuity plan](quality-and-continuity-implementation-plan-2026-10-27.md)
- [Bagdar: завершение пакетной симуляции](simulation-lab-continuation-2026-10-27.md)
- [Bagdar simulation lab: implementation plan](simulation-lab-plan-2026-10-27.md)
- [Stationary device acceptance checklist](stationary-device-acceptance-checklist-2026-10-27.md)

### Device performance and optional hardware

- [Условное использование аппаратуры телефона](optional-hardware-plan-2026-10-05.md)
- [План производительности Bagdar на Android](phone-performance-plan-2026-10-05.md)
- [Протокол измерения Core на телефоне](phone-performance-protocol-2026-10-05.md)
- [Bagdar: первый этап производительности на Android](phone-performance-stage1-report-2026-10-05.md)
- [Bagdar: речь под нагрузкой и размер Android APK](phone-performance-stage2-report-2026-10-05.md)
- [Bagdar: идентификаторы и доставка предупреждений](phone-performance-stage3-report-2026-10-05.md)
- [Bagdar: независимый запуск YOLO и depth](phone-performance-stage4-report-2026-10-05.md)

### Research capture and iPhone recording

- [Первая запись: подготовка без iPhone и Mac](first-capture-trial-2026-10-18.md)
- [Bagdar: исследовательский путь iPhone — 17 октября 2026](iphone-spatial-feasibility-2026-10-17.md)
- [Bagdar Research: запись реальных данных камеры](research-capture-guide-2026-10-11.md)
- [Сверка выбранной записи с manifest: 2026-10-11](research-capture-identity-evaluation-2026-10-11.md)
- [Bagdar: подготовка реального захвата RGB/depth](research-capture-report-2026-10-11.md)

### Perception, scene experiments and replay evidence

- [Bagdar AI: внутренние переходы и восстановление после SOS](bagdar-accessible-transitions-2026-10-12.md)
- [Bagdar: контекстный Blender-корпус и проверка perception → action](blender-context-evaluation-2026-09-23.md)
- [Bagdar: проверка детекторов на синтетических сценах препятствий](blender-detector-evaluation-2026-09-22.md)
- [Исправление оценки риска на парных Blender-сценах — 2026-10-04](blender-paired-correction-evaluation-2026-10-04.md)
- [Исправление полномочий generic geometry — 2026-10-04](blender-paired-correction-protocol-2026-10-04.md)
- [Результат нового набора Blender-сцен — 2026-10-04](blender-paired-scenes-evaluation-2026-10-04.md)
- [Парные Blender-сцены: протокол первого прогона](blender-paired-scenes-protocol-2026-10-04.md)
- [Полная площадь пикселя: независимые границы first-return](blender-scan-complete-envelope-protocol-2026-10-04.md)
- [Покрытие неподвижного обзора — 2026-10-04](blender-scan-coverage-evaluation-2026-10-04.md)
- [Полное покрытие неподвижного обзора — протокол](blender-scan-coverage-protocol-2026-10-04.md)
- [Exact topology of the canonical pixel partition](blender-scan-exact-partition-protocol-2026-10-04.md)
- [Дополнение к scan coverage: корреляция луча и глубины](blender-scan-height-envelope-protocol-2026-10-04.md)
- [Обработка обзора и свежесть под NCNN — 2026-10-04](blender-scan-processing-evaluation-2026-10-04.md)
- [Свежесть и стоимость обработки обзора — протокол v1](blender-scan-processing-protocol-2026-10-04.md)
- [Canonical projection of visible floor surfaces](blender-scan-watertight-protocol-2026-10-04.md)
- [Согласованные optical envelopes — дополнение v2](blender-synchronized-rig-bundle-protocol-2026-10-04.md)
- [Одновременный обзор: первый desktop этап — 2026-10-04](blender-synchronized-rig-evaluation-2026-10-04.md)
- [Одновременный синтетический обзор — протокол v1](blender-synchronized-rig-protocol-2026-10-04.md)
- [Bagdar: многокадровая проверка детекторов на Blender](blender-temporal-evaluation-2026-09-22.md)
- [Наблюдаемое пространство для тела — 2026-10-04](blender-visible-body-evaluation-2026-10-04.md)
- [Наблюдаемое пространство для тела — протокол этапа](blender-visible-body-protocol-2026-10-04.md)
- [Independent fast motion branch — 2026-10-03](camera-fast-motion-evaluation-2026-10-03.md)
- [Motion under concurrent neural load — 2026-10-04](camera-fast-motion-load-evaluation-2026-10-04.md)
- [Concurrent-load motion experiment — 2026-10-04](camera-fast-motion-load-protocol-2026-10-04.md)
- [Первые исправления после проверки сцен — 2026-10-07](camera-fast-motion-packed-evaluation-2026-10-07.md)
- [Исправление транспорта fast-motion — 2026-10-07](camera-fast-motion-packed-protocol-2026-10-07.md)
- [Independent fast motion shadow branch — 2026-10-03](camera-fast-motion-protocol-2026-10-03.md)
- [Strict SIMD2 fast-motion experiment — 2026-10-07](camera-fast-motion-simd-protocol-2026-10-07.md)
- [Независимая подача кадров и проверка ускоренного ядра — 2026-10-07](camera-fast-motion-stream-evaluation-2026-10-07.md)
- [Независимая подача кадров fast-motion — 2026-10-07](camera-fast-motion-stream-protocol-2026-10-07.md)
- [Видимое метрическое движение — 2026-10-03](camera-metric-motion-evaluation-2026-10-03.md)
- [Видимое метрическое движение — протокол до реализации](camera-metric-motion-protocol-2026-10-03.md)
- [Задержки и возраст camera evidence — 2026-10-03](camera-processing-age-evaluation-2026-10-03.md)
- [Задержки и возраст данных — 2026-10-03](camera-processing-age-protocol-2026-10-03.md)
- [Сопоставление видимых участков при изменении масштаба — 2026-10-03](camera-scale-motion-evaluation-2026-10-03.md)
- [Сопоставление при изменении масштаба — протокол до test](camera-scale-motion-protocol-2026-10-03.md)
- [Стабильность RANSAC и временные камерные сцены — 2026-10-03](camera-temporal-stability-evaluation-2026-10-03.md)
- [Протокол camera-temporal-passage-v1, до реализации и просмотра test](camera-temporal-stability-protocol-2026-10-03.md)
- [Привязка NCNN-треков к видимому проходу — 2026-10-03](camera-track-association-evaluation-2026-10-03.md)
- [Покрытие прохода при смене ракурса — 9 октября 2026](camera-view-coverage-evaluation-2026-10-09.md)
- [Camera view coverage experiment — 9 October 2026](camera-view-coverage-protocol-2026-10-09.md)
- [Проходы по видимым данным камеры — 2026-10-02](camera-visible-passage-evaluation-2026-10-02.md)
- [Положительный контроль полного объёма — 11 октября 2026](closed-volume-control-evaluation-2026-10-11.md)
- [Closed upper-volume control — 11 October 2026](closed-volume-control-protocol-2026-10-11.md)
- [MiDaS → Depth Anything V2 Small: результат первого эксперимента](depth-anything-bakeoff-2026-10-05.md)
- [Проём: проверка поверхности и причин неопределённости](doorway-evidence-diagnostics-2026-10-02.md)
- [Ego motion and separated risk — 10 October 2026](ego-motion-evaluation-2026-10-10.md)
- [Ego motion and separated risk protocol — 10 October 2026](ego-motion-protocol-2026-10-10.md)
- [Исправление приоритета доказательств — 10 октября 2026](evidence-authority-fix-evaluation-2026-10-10.md)
- [Current volume authority repair — 10 October 2026](evidence-authority-fix-protocol-2026-10-10.md)
- [Уменьшение ложных остановок: поверхность и неопределённость наблюдения](false-stop-reduction-2026-10-01.md)
- [Bagdar Spatial Safety — Model Bake-off Report](model-bakeoff-report.md)
- [Откуда берётся сигнал движения — 10 октября 2026](motion-origin-evaluation-2026-10-10.md)
- [Motion origin experiment — 10 October 2026](motion-origin-protocol-2026-10-10.md)
- [Восстановление после неизвестности прохода — 2026-10-02](passage-recovery-evaluation-2026-10-02.md)
- [Разбор остановок в path-clear — 7 октября 2026](path-clear-stop-diagnosis-evaluation-2026-10-07.md)
- [Path-clear stop diagnosis contract — 2026-10-07](path-clear-stop-diagnosis-protocol-2026-10-07.md)
- [Ускорение проверки объёма: 2026-10-11](scalar-scan-processing-evaluation-2026-10-11.md)
- [Scalar scan processing — 2026-10-11](scalar-scan-processing-protocol-2026-10-11.md)
- [Исправления логики сцен — 16–17 октября 2026](scene-logic-fixes-2026-10-16.md)
- [Непрерывная последовательность first-return — 9 октября 2026](sequence-first-return-evaluation-2026-10-09.md)
- [Eleven-frame first-return replay — 9 October 2026](sequence-first-return-protocol-2026-10-09.md)
- [Свежие ракурсы одной камеры — 11 октября 2026](single-camera-fresh-scan-evaluation-2026-10-11.md)
- [Single-camera fresh scan window — 2026-10-11](single-camera-fresh-scan-protocol-2026-10-11.md)
- [Сокращённый обзор одной камеры: результат 2026-10-11](single-camera-minimal-scan-evaluation-2026-10-11.md)
- [Minimal finite camera scan — 2026-10-11](single-camera-minimal-scan-protocol-2026-10-11.md)
- [Одна камера: проверка наблюдаемости прохода — 11 октября 2026](single-camera-observability-evaluation-2026-10-11.md)
- [Single-camera observability preflight — 2026-10-11](single-camera-observability-protocol-2026-10-11.md)
- [Bagdar Spatial Safety — Sonar Research Report](sonar-research-report.md)
- [Покадровая диагностика STOP — 17 октября 2026](stop-cause-diagnostics-2026-10-17.md)
- [Bagdar STOP logic audit — 19 October 2026](stop-logic-audit-2026-10-19.md)
- [Синхронные ракурсы и ложные остановки — 9 октября 2026](synchronized-passage-evaluation-2026-10-09.md)
- [Synchronized passage transfer experiment — 9 October 2026](synchronized-passage-protocol-2026-10-09.md)
- [Проём: метрическая геометрия в синтетическом shadow-прогоне](synthetic-passage-shadow-2026-10-02.md)
- [Локализация второго трека — 9 октября 2026](track-first-return-evaluation-2026-10-09.md)
- [Primary first-return bounds experiment — 9 October 2026](track-first-return-protocol-2026-10-09.md)
- [Передача оптических измерений: 2026-10-11](typed-scan-transport-evaluation-2026-10-11.md)
- [Immutable typed optical transport — 2026-10-11](typed-scan-transport-protocol-2026-10-11.md)
- [Карта неизвестного объёма — 18 октября 2026](unknown-volume-diagnosis-2026-10-18.md)
- [Проверка замороженного runtime на новых сценах — 10 октября 2026](volume-holdout-evaluation-2026-10-10.md)
- [Frozen-runtime independent scene check — 10 October 2026](volume-holdout-protocol-2026-10-10.md)
- [Whole visible track evidence — 10 October 2026](whole-track-evidence-evaluation-2026-10-10.md)
- [Whole visible track evidence — 10 October 2026](whole-track-evidence-protocol-2026-10-10.md)

### Repository navigation

- [Repository map](repository-structure.md)

## Preserved evidence and references

- `_baseline_logs/`: deliberate benchmark receipts, reports and associated evidence.
- `_baseline_sources/`: frozen source snapshots bound to earlier experiments.
- `design/`: design artifacts and previews.
- [Historical documents and prior README](archive/README.md)
- [Archived one-off patch scripts](../tool/archive/README.md)
- [Offline model-export sources](../model_export/README.md)

Keep named evidence stable. New generated runs belong in ignored `output/`;
temporary logs and exploratory scripts belong in ignored `scratch/`.
