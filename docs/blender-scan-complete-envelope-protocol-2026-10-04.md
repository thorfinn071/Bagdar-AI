# Полная площадь пикселя: независимые границы first-return

Измеренный scan-coverage v1 закрыл body во всех пяти обычных проходимых
snapshots, но у person-side оставил четыре ближние body cells unknown.
Исходный lower-Z экстраполирует глубину частичного треугольника на весь
пиксель; на косой поверхности это безопасная, но излишне малая граница.
Height-only экспорт остановлен после проверки математики и ray witnesses:
неполные данные сохранены, итогом полного replay они не считаются.

Следующий вариант экспортирует height bounds и независимый first-Z lower
по тому же аналитическому разбиению видимой площади пикселя. Минимум Z,
максимум Z и extrema высоты берутся на вершинах реально видимых фрагментов.
Любая дырка или исчерпание бюджета дают unknown, а не интерполяцию.
Тонкая ближайшая поверхность обязана войти в first-Z minimum.

Четыре исходных массива scan v1 остаются побайтово прежними. Дополнительный
certified lower-Z может быть сильнее прежней консервативной границы, но
обязан быть не больше каждого независимого ray-cast witness; это новое
геометрическое свидетельство, а не ослабление unknown threshold.
Экспериментальный wrapper передаёт этот отдельный free-space bound прежнему
body producer и отдельно доказывает floor через height bounds. Источники
body evidence и floor evidence не заменяют друг друга.

Ракурсы и время те же 12 × 200 мс, запрос прежний 0,9 × 1,85 м,
forward 0,2–3,5 м. Цель: 6/6 passable snapshots measuredClear,
6/6 hazards blocked, все strict stale scans unavailable. Missing upward
views, first-Z/height bounds/depth, relative units, mismatched pose/session
и malformed intervals должны отвергаться. Normal camera и активные
подсказки не меняются. Moving false stops и Android timing не измеряются.

Все старые источники и отчёты сохраняются, `promotionAllowed=false`.
