# NCNN model-contract fixtures

Phase 1 exit gate: the same RGB/YUV frames must produce spatially consistent
depth from this tree's Android NCNN model and a reference MiDaS-small export.

Required scenes (tiny, privacy-safe crops):

- flat indoor corridor
- wall filling the walking corridor
- chair / box
- narrow pole / bollard on the center line
- outdoor walkway

`reference_outputs.json` is generated explicitly from the pinned ONNX
reference runtime and NCNN Python CPU runtime:

```powershell
tools\ncnn\.venv\Scripts\python.exe tools\ncnn\parity_test.py `
  --fixture test\fixtures\ncnn_contract\reference_outputs.json
```

The generator is read-only unless `--fixture` or `--output` is supplied. The
fixture records all model hashes and limits its claim to desktop inference
parity; Android bridge/device parity remains an R8 gate.
The correlation unit test must report `missing fixture` rather than pass.

When captured, use this schema:

```json
{
  "cases": [
    {
      "name": "flat_corridor",
      "width": 256,
      "height": 256,
      "reference": [0.0],
      "native": [0.0]
    }
  ]
}
```

`reference` and `native` must contain corresponding flattened maps. The test
filters non-finite pairs and requires Spearman rank correlation >= 0.90.

Do not check in raw camera dumps without explicit developer consent.
