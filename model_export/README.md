# Offline model export

This directory contains export scripts, pinned requirements and candidate
manifests. It is separate from the packaged models in `assets/`.

- `export_candidates.py`: YOLO candidate exports.
- `prepare_depth_anything_v2.py` and `depth_anything_v2/`: depth candidate preparation.
- `requirements-lock.txt`: export environment requirements.
- `candidates/manifest.json`: candidate identity and export settings.
- `local/yolo11n.pt`: extra checkpoint formerly at the repository root, retained locally.

Downloaded `.pt` and generated `.onnx` files are ignored. Preserve manifests and
source scripts in Git; provision binaries using the relevant export protocol.
The existing scripts still use `model_export/yolo11n.pt` for their primary
checkpoint. Moving the extra root copy did not change that path.

Candidate export or desktop parity does not authorize runtime replacement.
See [the model bakeoff report](../docs/model-bakeoff-report.md).
