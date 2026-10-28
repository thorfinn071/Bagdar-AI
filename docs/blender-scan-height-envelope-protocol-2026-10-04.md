# Дополнение к scan coverage: корреляция луча и глубины

Первый вариант обзора закрывает body volume, но на дальнем полу смешивание
крайних Z с крайними лучами даёт завышенный интервал высоты. Первый вариант,
его исходники и пакеты сохраняются. Новый вариант добавляет independent
whole-pixel bounds высоты первой видимой поверхности в walking frame.

Высота на видимом фрагменте вычисляется как отношение аффинных функций
screen coordinates с положительной inverse depth; экстремумы достигаются
на вершинах выпуклого фрагмента. Геометрия скрытых поверхностей не используется
для clearance. Floor proof требует полного footprint и valid bounds;
body proof продолжает использовать прежний conservative free-Z source.
Никакая уверенность пола не переносится в ненаблюдаемый headroom.

Экспортируются только два height bounds для 144 ранее выбранных видов.
Все четыре прежних массива при повторном вычислении должны побайтово
совпасть с вариантом v1. Новые height intervals проверяются по независимым
ray-cast witnesses. Consumer получает heights и optical packets, без mesh
или semantic labels; отдельный synthetic wrapper сохраняет старый source.

Сравнение: результат v1 на тех же 12 frozen snapshots и v2 с height proof.
Цель остаётся 6/6 проходимых snapshots с полным body/floor proof,
6/6 hazard snapshots blocked, ноль hazard/stale measuredClear.
Single view, отсутствие upper bounds, missing depth/height, relative units,
pose/session mismatch и отсутствие upward views должны оставаться unavailable.

Временной контракт прежний: 2,2 с накопления диагностического обзора,
runtime freshness 100 мс. Геометрическое measuredClear не является
разрешением движения; normal camera, модели и assistive delivery не меняются.
Все данные известного regression corpus, `promotionAllowed=false`.
