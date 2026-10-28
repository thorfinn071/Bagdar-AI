# Независимая подача кадров fast-motion — 2026-10-07

Этот этап исправляет измерительный harness. Packed allocation fix и все
прежние source/receipts остаются без изменений. Обычная камера не подключает
экспериментальный metric-motion source; `promotionAllowed=false`.

## Причина изменения

Прежний replay выдавал fast-result раньше NN, но затем ожидал завершения NN
перед следующим предложением кадра. При длинном inference возраст последующих
заранее записанных captures мог превысить TTL ещё до входа в fast worker.
Это не соответствует независимой подаче camera callbacks.

Уточнение к предыдущему packed evaluation/protocol: файл
`camera_processing_ncnn_worker.py` запускает **только MiDaS Small NCNN**.
Фраза «YOLO/MiDaS» в прежнем описании нагрузки неточна. YOLO в этих elapsed
измерениях не выполнялся; проверка YOLO в первоначальной QA была отдельной.
Прежние замеры и замороженные документы сохранены, их timing выводы не
подменяются новым протоколом.

## Подача и нагрузка

- 109 известных synthetic captures/16 layouts с исходными timestamp, RGB,
  first-return metric depth, whole-pixel bounds и pose. Это не MiDaS depth.
- Отдельные timers назначают callbacks с исходным интервалом 200 мс.
  Feed не ожидает NN или fast completion. Joining выполняется после подачи.
  При callback error оставшиеся timers отменяются; ошибки не скрываются.
- Callback age и возраст до `worker.offer` измеряются отдельно. Поздний
  callback сохраняет исходный capture timestamp; он не становится свежим.
- Нагрузка MiDaS использует настоящий `PerceptionScheduler`: depth-only,
  максимум один активный inference, zero queue. Busy capture пропускается
  нейросетью, но продолжает поступать в fast worker. Пропуски NN считаются.
  Raw NN outputs сверяются с pinned данными и не передаются fast producer.
- MiDaS CPU, one thread, no Vulkan, 10 warmups — настройки прежнего Python
  worker. Загрузка fixture/model исключена из capture clock.
- Clock начинается с первого исходного timestamp + 2000 мкс и advances
  по Stopwatch. Это desktop callback simulation, не измерение sensor capture.
- Control и packed версия используют один AOT executable и одинаковый caller;
  `--control` выбирает замороженный load worker. Native matcher C/ABI тот же.

## Контракты и критерии

TTL текущего fast кадра остаётся **100000 мкс**. Pair interval, oldest-evidence
expiry, identity/session/provider/clock admission, single-use release,
one-active/one-newest-pending и shadow/unknown правила прежние.

Fixed-clock functional режим проверяет все 109 diagnostic maps против
исходного `camera_processing_parity.json` для обеих версий. Он не измеряет
задержку. Tests проверяют независимую подачу при зависшем NN/fast result,
busy skips без pending queue, inference errors, stale/session rejection,
clock failure, отмену callbacks и неизменность поздних timestamp.

Elapsed сравнение: три повтора каждой версии в чередующемся порядке
control-1, packed-1, packed-2, control-2, control-3, packed-3. Во время замеров
не запускаются Flutter tests/analyzer. Каждый elapsed output — новый файл.
Запрет перезаписи обязателен. Тот же корпус не становится новым holdout.

Отдельно считаются своевременные эталонные risk updates, unexpected risks,
тайм-ауты любых кадров, callback/offer age, stale admissions, free-space
authority, нагрузка/пропуски NN. Успех risk updates не означает, что все
109 кадров прошли TTL, и не доказывает Android/capture-to-command readiness.

55/55 paired false stops, качество YOLO, полнота body-volume observation,
целевой телефон и controlled walking в этом этапе не исправляются и не
сертифицируются. Они остаются отдельными открытыми ограничениями.

## Воспроизведение

```powershell
dart run tool/model_benchmark/evaluate_fast_camera_motion_stream.dart --check
python tool/model_benchmark/verify_fast_camera_motion_stream.py --check
```

После сборки — каждый запуск с новым именем output:

```powershell
& scratch/fast-camera-stream-verification/replay.exe --elapsed-nn scratch/stream-control-new.json C:/Users/Nurik/Desktop/bagdar_app/scratch/fast-camera-stream-verification/fast_motion_match.dll --control
& scratch/fast-camera-stream-verification/replay.exe --elapsed-nn scratch/stream-packed-new.json C:/Users/Nurik/Desktop/bagdar_app/scratch/fast-camera-stream-verification/fast_motion_match.dll
```
