# Согласованные optical envelopes — дополнение v2

Первый v1 corpus остаётся неизменным. Его elapsed receipts сохраняют отказ
consumer: exact floor-height supplement мог сертифицировать height interval
пикселя, у которого complete renderer оставил first-Z unknown. Такая комбинация
не допускается. Быстрый validation failure не доказывает скорость coverage.

v2 не меняет scene/camera/time/RGB/range/validity/free-Z. Для пикселей с новым
height interval и отсутствующим first-Z повторно вычисляется единый bundle
(surface upper, height lower/upper, first lower) через frozen exact rational
partition и canonical near clipping. Bundle публикуется только при полном
покрытии pixel footprint реально видимыми first returns. Любая дырка оставляет
весь bundle unknown. Первые v1 arrays и квитанции сохраняются; новые assets,
ray witnesses и source hashes записываются отдельно. Coverage consumer,
freshness, camera grid, physical scene dimensions и labels не меняются.

Это исправление целостности пакета до допуска. Параметры сцены не подгоняются
под итоговую полноту. Новый timer включает настоящий coverage только для
здоровых bundles. Strict 100 ms и shadow-only остаются обязательными.
