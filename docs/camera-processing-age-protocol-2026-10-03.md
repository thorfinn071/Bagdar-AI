# Задержки и возраст данных — 2026-10-03

Отдельный software/shadow этап. `promotionAllowed=false`. Предыдущие freezes,
исходники, labels и отчёты не переписываются. camera-scale-motion-v1 теперь
известный regression corpus, не новый holdout. Улучшение общей точности на
независимых новых сценах здесь не заявляется.

1. Сравнить frozen scale matcher и отдельный optimized matcher на одинаковых
   preloaded inputs, после прогрева, в чередующемся порядке. Отдельно измерять
   fixture IO/decompression/input construction, motion compute и реальные
   последовательные стадии. NCNN CPU запускается с прежними model/preprocess,
   num_threads=1; проверяется совпадение float32 output с frozen assets.
2. Оптимизация ограничена повторными вычислениями optical axis, bounds,
   проекции и bilinear адресации. Порядок SAD суммирования, feature selection,
   winner/uniqueness/reverse consistency, motion risk и depth bounds сохраняются.
   Полные диагностические результаты должны совпасть на каждом входе, включая
   известные stationary/yaw/occluded/textureless и ошибки идентичности.
3. Добавить opt-in processing gate с injected monotonic clock в общей UTC
   capture domain. Возраст текущего кадра <=100 ms проверяется до compute,
   после compute и перед выдачей. Ограничение oldest+400 ms сохраняется.
   Опоздание, clock regression, identity/session/provider loss и compute failure
   уничтожают пару и право применения. Положительный риск не отменяет legacy
   motion/physical/unknown history. Неизвестность не означает clear.
4. Очередь содержит один newest pending frame. Capture timestamps и frame ids
   должны расти; dropped frames не подменяются повторами. Pair gap за пределами
   50–300 ms остаётся unavailable. Session reset/provider loss очищают очередь.
5. Детерминированный elapsed replay проверяет deadline boundaries, compute и
   dispatch overruns, очередь, восстановление и настоящий scene/planner path.
   Отдельный measured replay продвигает clock на фактические Stopwatch времена;
   precomputed NN replay явно отделяется от живого NCNN CPU прохода. Внешние
   capture/transport/device расходы не выдаются за измеренные.

Acceptance: zero stale application; bit-identical функциональные outputs
optimized/frozen на regression corpus; 18/18 approach risk pairs в функциональном
режиме; zero unsafe continue/unjustified clear. В elapsed режиме все late данные
считаются unavailable; stop из неизвестности не считается наблюдением движения.
Отдельно публикуются p50/p95, queue drops, stale packets и hazardous reaction.
Не обещается достижение 100 ms: NCNN сам может превышать бюджет. TTL не расширять.
После targeted checks — последовательный полный Core RC с обязательным gate
нового отчёта. Android/device calibration/runtime/walking остаются not_run.
