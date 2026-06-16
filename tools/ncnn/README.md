# NCNN depth runtime — bring-up guide

Полная инструкция от чистого рабочего дерева до работающего NCNN depth-провайдера в Bagdar.

## TL;DR (one-time setup)

```powershell
# 1. Конвертация модели (Python)
cd tools/ncnn
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
.\download_ncnn_tools.ps1            # скачивает onnx2ncnn.exe + ncnnoptimize.exe
python convert_midas.py               # → assets/midas_small.ncnn.{param,bin}
python parity_test.py                 # parity vs TFLite (опционально)
deactivate
cd ../..

# 2. Android runtime
.\tools\ncnn\download_ncnn_android.ps1   # → android/app/src/main/cpp/third_party/ncnn/

# 3. pubspec.yaml — добавить в раздел assets:
#    - assets/midas_small.ncnn.param
#    - assets/midas_small.ncnn.bin

# 4. Сборка
flutter clean
flutter pub get
flutter run     # на устройстве
```

В логе должно появиться:

```
DepthProviderFactory: activated NCNN (vulkan=true)   # или false для CPU
BagdarNcnn: init: ok vulkan=1 threads=2 in=... out=...
```

## Пайплайн конвертации модели

```
midas_small_int8.tflite  (INT8, 15.9 MB)
   │  tflite2onnx  (де-квантизирует в FP32)
   ▼
midas_small_fp32.onnx    (FP32, ~64 MB временный)
   │  onnx2ncnn
   ▼
midas_small.ncnn.param   (текст, ~50 KB)
midas_small.ncnn.bin     (FP32, ~64 MB временный)
   │  ncnnoptimize -fp16
   ▼
midas_small.ncnn.param   (финал)
midas_small.ncnn.bin     (FP16, ~32 MB)
```

**FP16 как baseline** — без калибровки. INT8 квантизация — отдельный шаг (sprint 2), требует калибровочного датасета.

## Требования

- **Python 3.10+**
- **ncnn binary tools**: `onnx2ncnn`, `ncnnoptimize`. Берутся из релизов ncnn:
  https://github.com/Tencent/ncnn/releases — раздел `ncnn-YYYYMMDD-windows-vs2019.zip` (для Windows).
  Распаковать и положить пути в PATH либо в `tools/ncnn/bin/`.

## Установка

```powershell
cd tools/ncnn
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Скачать ncnn binaries (один раз)
.\download_ncnn_tools.ps1
```

## Запуск конвертации

```powershell
python convert_midas.py
```

Скрипт:
1. Прочитает `assets/midas_small_int8.tflite`
2. Конвертирует TFLite → ONNX FP32 → NCNN FP32 → NCNN FP16
3. Запишет в `assets/midas_small.ncnn.param` + `assets/midas_small.ncnn.bin`
4. Запустит `parity_test.py` — сравнит outputs TFLite vs NCNN на 5 тестовых кадрах

## Verification

```powershell
python parity_test.py
```

Допустимый pixel-wise mean abs diff: **< 0.03** (FP32 нормализованный output).

## Куда дальше

- Если parity прошла → committed `.ncnn.param` + `.ncnn.bin` в assets, добавляем в `pubspec.yaml` assets section
- Если parity провалилась → лог сохранится в `tools/ncnn/parity_report.json`, пересмотреть конверсию

---

## Graceful fallback

Если хотя бы одно из этих условий не выполнено:

- `third_party/ncnn/lib/<abi>/libncnn.a` отсутствует (CMake скипает NCNN из сборки)
- `assets/midas_small.ncnn.param` или `.bin` не объявлены в `pubspec.yaml`
- `bagdar_ncnn_init` вернул non-zero (битая модель, OOM, Vulkan недоступен и fp16-arith отказал)

— `DepthProviderFactory.createAndInit` автоматически переходит на MiDaS NNAPI → MiDaS CPU → FocalLength. Приложение работает в любом случае.

## Что проверить после сборки (D4.2 field-test)

```
adb logcat | findstr /R "DepthProviderFactory BagdarNcnn NcnnDepthProvider NcnnDepthBridge"
```

Бенчмарк inference time:
- Открыть camera screen в Bagdar
- В settings → dev → смотреть `lastInferenceMs` в `DepthProvider.lastInferenceMs`
- Сравнить с эталоном TFLite (было ~180мс на SD680, ~85мс на SD G1)

Ожидаемые результаты NCNN FP16:

| Чип | Vulkan | CPU |
|---|---|---|
| Snapdragon G1 | ~40мс | ~80мс |
| Snapdragon 680 | ~80мс | ~120мс |
| MTK low-tier (BRP-NX1) | нет | ~150–200мс |

Если inference > 300мс — NCNN не даёт преимущества на этом устройстве; полезно рассмотреть INT8 квантизацию в sprint 2 (требует calibration dataset).
