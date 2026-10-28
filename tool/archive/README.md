# Historical one-off scripts

`sos-fixes/` preserves the old root `fix_camera.py`, `fix_fall.py`, `fix_sos.py`
and `fix_strings.py` exactly as found during cleanup on 2026-10-27.

They patch historical source text through machine-specific absolute paths and
are not reusable maintenance commands. Do not run them against the current app.
Current behavior belongs in application code and its tests.
