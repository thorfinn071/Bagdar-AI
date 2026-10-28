# Сопоставление при изменении масштаба — протокол до test

Отдельный `camera-scale-motion-v1`, shadow-only, `promotionAllowed=false`.
Прежний metric-motion-v1 и его freeze сохраняются. Его approach — известная
регрессия разработки, не новый test. MiDaS/NCNN и preprocessing закреплены;
метры берутся только из первой видимой метрической поверхности.

Сравнение на одинаковых RGB: frozen fixed-patch источник, распределение признаков
по кадру с прежним matcher (ablation), распределение + метрическое масштабирование.
У нового matcher предполагается локальная плоскость передней поверхности;
отношение оптических глубин и относительный поворот камер задают локальный warp.
Это гипотеза соответствия, не доказательство идентичности материала. Высокая
ошибка, неоднозначность, неограниченный depth, обратная несогласованность и выход
за поддерживаемый масштаб дают unknown. Порог риска 3 участка, motion 0,20 м/с,
ошибка RGB 0,065, uniqueness 0,015, reverse 1 pixel, age 100 ms и pair 50–300 ms
сохранены. Новый источник только добавляет риск через прежний opt-in адаптер;
не отменяет legacy motion, unknown, физические риски или историю остановки.

Validation: approach, approach-fast, receding, stationary, camera-yaw, crossing.
Test: approach-slow, approach-fast, approach-small, receding, stationary,
camera-yaw, mixed, occluded, textureless, wide. Полные геометрии и seeds различны.
Семь реальных кадров с шагом 200 мс; static wide — прежние девять направлений
yaw −60/0/+60, pitch −65/−15/+35 и возврат, камера на высоте 1,55 м.
Диапазон запроса 0,2–3,5 м и тело 0,9×1,8 м сохраняются. Динамические сцены
недостаточно наблюдаемы для global clearance; wide scan имеет номинальную
разметку достаточности независимо от решений. Неполное покрытие producer
публикуется отдельно и не исправляется переименованием labels после test.

Scorer после решения получает отдельную маску **видимой** поверхности объекта
и физическую скорость. Это позволяет отличить совпадения объекта от фона и
проверить включение истинной скорости в интервалы. Маски/скорости/геометрия
не входят в producer, калибровку или planner. Unmatched не считаются stationary.

До первого test: unit/negative cases, известная регрессия, validation, analyzer,
write-once freeze исходников, параметров, protocol и assets. После freeze test
не подгоняется. Цель: больше корректных object approach matches/risk frames,
без ложного движения stationary/camera-only и без unsafe/unjustified clear.
Ложные остановки, holds и latency публикуются отдельно; достижение motion
coverage не означает снижение ложных остановок или phone readiness.

Отрицательные проверки: stale/future/reorder/session/provider/frame/transform,
pose/projection/units/bounds, однотонные и повторяющиеся RGB, depth noise/holes,
неподдерживаемый масштаб, окклюзия, конфликт и запрет hidden geometry/IO.
Desktop timings не меняют TTL; замеры времени хранятся отдельно от --check.
