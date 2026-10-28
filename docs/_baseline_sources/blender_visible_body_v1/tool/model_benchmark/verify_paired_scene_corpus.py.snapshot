"""Hash/annotation/visibility checks and browsable previews for the new corpus."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "test/fixtures/spatial_safety/blender-paired-holdout-v1"
SPEC = ROOT / "tool/blender/paired_scene_spec_v1.json"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def checked(root, asset):
    name = asset["path"]
    if not isinstance(name, str) or not name or name.startswith("/") or "\\" in name or ":" in name or ".." in Path(name).parts or Path(name).is_absolute():
        raise ValueError(f"Unsafe asset path: {name!r}")
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file() or sha(path) != asset["sha256"]:
        raise ValueError(f"Missing, escaped or modified asset: {name}")
    return path


def pgm16(path):
    with path.open("rb") as stream:
        if stream.readline().strip() != b"P5":
            raise ValueError("Expected P5")
        w, h = map(int, stream.readline().split())
        if stream.readline().strip() != b"65535":
            raise ValueError("Expected uint16 depth")
        raw = stream.read()
    if len(raw) != w * h * 2:
        raise ValueError("Depth size mismatch")
    return np.frombuffer(raw, dtype=">u2").reshape(h, w)


def old_rgb_hashes():
    found = set()
    def visit(value):
        if isinstance(value, dict):
            rgb = value.get("rgb")
            if isinstance(rgb, dict) and "sha256" in rgb:
                found.add(rgb["sha256"])
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    for folder in CORPUS.parent.iterdir():
        if folder != CORPUS and folder.is_dir():
            for path in folder.glob("*manifest.json"):
                visit(read_json(path))
    return found


def load_corpus(root=CORPUS, pilot=False):
    manifest = read_json(root / "corpus-manifest.json")
    spec = read_json(SPEC)
    if manifest["corpusId"] != spec["corpusId"] or manifest["schemaVersion"] != 1 or manifest["pilotOnly"] != pilot:
        raise ValueError("Wrong corpus identity or pilot scope")
    if manifest["promotionAllowed"] is not False or manifest["containsRecordedMedia"] is not False:
        raise ValueError("Wrong delivery/source scope")
    for name, expected in manifest["sources"].items():
        checked(ROOT, {"path": name, "sha256": expected})
    entries = spec["scenes"][:2] if pilot else spec["scenes"]
    sequences = manifest["sequences"]
    if [s["sceneId"] for s in sequences] != [s["id"] for s in entries]:
        raise ValueError("Incomplete or reordered scene set")
    if len({e["id"] for e in entries}) != len(entries):
        raise ValueError("Duplicate scene identity")
    if (manifest["width"], manifest["height"]) != (spec["width"], spec["height"]):
        raise ValueError("Image size drift")
    old_hashes = old_rgb_hashes()
    output = []
    for seq, entry in zip(sequences, entries):
        checked(root, seq["scene"])
        labels = read_json(checked(root, seq["annotations"]))
        if labels["parameters"] != entry or labels["physicalHazard"] != entry["hazard"] or labels["referencePassable"] == entry["hazard"]:
            raise ValueError("Annotation drift from predeclared geometry")
        if labels["sceneId"] != entry["id"] or labels["pair"] != entry["pair"]:
            raise ValueError("Annotation identity mismatch")
        if labels["userMoving"] != (entry["cameraAdvanceM"] > 0):
            raise ValueError("User motion intent drift")
        if labels["compatibleCocoClassIds"] != ([0] if entry["kind"] == "person" else []):
            raise ValueError("Invented COCO class")
        if labels["hazardOnsetMs"] != (0 if entry["hazard"] else None) or labels["latestStopOffsetMs"] != (spec["latestStopAfterOnsetMs"] if entry["hazard"] else None):
            raise ValueError("Changed timing labels")
        frames = seq["frames"]
        if [f["frameIndex"] for f in frames] != list(range(len(spec["frameOffsetsMs"]))):
            raise ValueError("Incomplete frame sequence")
        if [f["capturedOffsetMs"] for f in frames] != spec["frameOffsetsMs"]:
            raise ValueError("Timestamp drift")
        rows = []
        for f in frames:
            paths = {k: checked(root, f[k]) for k in ("rgb", "depth", "semantic")}
            if f["rgb"]["sha256"] in old_hashes:
                raise ValueError("Reused old-corpus RGB")
            with Image.open(paths["rgb"]) as image:
                rgb = np.array(image.convert("RGB"))
            with Image.open(paths["semantic"]) as image:
                mask = np.array(image)
            depth = pgm16(paths["depth"])
            h, w = spec["height"], spec["width"]
            if rgb.shape != (h, w, 3) or mask.shape != (h, w) or depth.shape != (h, w):
                raise ValueError("RGB/depth/mask alignment mismatch")
            if np.any((depth == 0) != (mask == 0)) or not set(np.unique(mask)).issubset({0, 1, 2, 4, 5, 6, 8, 10}):
                raise ValueError("Invalid visible-return semantics")
            if rgb.std() < 5 or len(np.unique(rgb.reshape(-1, 3), axis=0)) < 50:
                raise ValueError("Uninformative RGB render")
            if np.mean(np.all(rgb >= 250, axis=2)) > .15:
                raise ValueError("Overexposed RGB render")
            hazard_class = {"box": 4, "drop": 6, "person": 10}.get(entry["kind"], 5 if entry["pair"] == "headroom" else 2)
            visible_pixels = int((mask[:, w // 3:w * 2 // 3] == hazard_class).sum())
            if entry["hazard"] and visible_pixels < 40:
                raise ValueError(f"Scoring hazard outside central FOV: {entry['id']}/{f['frameIndex']}")
            pose = f["cameraPose"]
            if abs(pose["fx"] - pose["fy"]) > .001 or pose["fx"] <= 0 or pose["pitchDownDeg"] != spec["camera"]["pitchDownDeg"]:
                raise ValueError("Invalid camera projection")
            rows.append({**f, "paths": paths, "visibleScoringPixels": visible_pixels})
        output.append({**seq, "labels": labels, "frames": rows})
    pairs = sorted({entry["pair"] for entry in entries})
    for pair in pairs:
        members = [s for s in output if s["pair"] == pair]
        if len(members) != 2 or sorted(s["labels"]["physicalHazard"] for s in members) != [False, True]:
            raise ValueError("Incomplete matched contrast pair")
        if members[0]["labels"]["parameters"]["appearanceSeed"] != members[1]["labels"]["parameters"]["appearanceSeed"]:
            raise ValueError("Appearance differs across contrast pair")
        for a, b in zip(members[0]["frames"], members[1]["frames"]):
            if a["cameraPose"] != b["cameraPose"] or a["rgb"]["sha256"] == b["rgb"]["sha256"]:
                raise ValueError("Pair must share camera pose and differ visibly")
    return manifest, output


def previews(root, sequences):
    folder = root / "previews"
    folder.mkdir(exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
    sheet = Image.new("RGB", (980, ((len(sequences) + 1) // 2) * 385), "#111827")
    draw = ImageDraw.Draw(sheet)
    for index, seq in enumerate(sequences):
        pair_index, column = divmod(index, 2)
        frames = [Image.open(f["paths"]["rgb"]).convert("RGB") for f in seq["frames"]]
        frames[0].save(folder / f"{seq['sceneId']}.gif", save_all=True, append_images=frames[1:], duration=200, loop=0)
        tile = frames[5].resize((440, 330))
        x, y = 20 + column * 480, pair_index * 385
        sheet.paste(tile, (x, y + 42))
        draw.text((x, y + 14), seq["sceneId"] + ("  HAZARD" if seq["labels"]["physicalHazard"] else "  PASSABLE"),
                  font=font, fill="#fca5a5" if seq["labels"]["physicalHazard"] else "#86efac")
        for image in frames:
            image.close()
    sheet.save(folder / "overview.png")
    records = [{"path": p.relative_to(root).as_posix(), "sha256": sha(p)} for p in sorted(folder.iterdir()) if p.suffix in {".gif", ".png"}]
    (folder / "manifest.json").write_text(json.dumps({"sourceManifestSha256": sha(root / "corpus-manifest.json"), "assets": records}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--root", default=str(CORPUS))
    p.add_argument("--pilot", action="store_true")
    p.add_argument("--previews", action="store_true")
    args = p.parse_args()
    root = Path(args.root).resolve()
    if not root.is_relative_to(ROOT):
        raise ValueError("Corpus must remain inside workspace")
    _, sequences = load_corpus(root, args.pilot)
    if args.previews:
        previews(root, sequences)
    print(json.dumps({"scenes": len(sequences), "frames": sum(len(s["frames"]) for s in sequences), "completePairs": len(sequences) // 2, "integrity": "pass"}))
