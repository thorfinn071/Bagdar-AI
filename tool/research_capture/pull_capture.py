"""List or explicitly export a local Research capture using a debuggable APK.

Never installs, launches, records, deletes, uploads, or clears app data.
Raw media export requires a recording ID and a new output folder outside Git.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

from audit_capture import audit, CaptureError, MAX_BYTES, RECORDING_ID, require

PACKAGE = "com.example.bagdar"
ID = RECORDING_ID
REPO = Path(__file__).resolve().parents[2]


def checked_output(path: Path):
    require(path.is_absolute(), "output must be an absolute path")
    target = path.resolve()
    require(not target.is_relative_to(REPO), "raw recordings must stay outside this repository")
    require(not target.exists(), "output already exists; choose a new directory")
    require(not any((p / ".git").exists() for p in target.parents), "raw recordings cannot be exported into a Git checkout")
    return target


def unpack(archive: Path, recording: str, output: Path):
    require(ID.fullmatch(recording), "invalid recording ID")
    output = checked_output(output)
    with tarfile.open(archive, "r:") as tar:
        entries = []
        names = set()
        total = 0
        for member in tar:
            require(len(entries) < 256, "too many archive entries")
            require("\\" not in member.name and ":" not in member.name, "invalid archive path")
            parts = PurePosixPath(member.name)
            require(not parts.is_absolute() and all(p != ".." for p in parts.parts) and
                    parts.parts and parts.parts[0] == recording, "archive escapes recording")
            relative = PurePosixPath(*parts.parts[1:])
            name = relative.as_posix()
            require(name not in names, "duplicate archive member")
            names.add(name)
            require(member.isfile() or member.isdir(), "archive links and special files are forbidden")
            allowed_file = name in ("manifest.json", "pending.json", "frames.jsonl", "manifest.json.tmp", "pending.json.tmp") or (
                len(relative.parts) == 2 and relative.parts[0] == "payloads" and
                re.fullmatch(r"[0-9]{4}-(?:rgb|depth|confidence)-[0-2]\.bin", relative.parts[1]))
            require((member.isdir() and name in (".", "payloads")) or (member.isfile() and allowed_file), "unexpected archive entry")
            total += member.size
            require(0 <= member.size <= MAX_BYTES and total <= MAX_BYTES + 2 * 1024 * 1024, "archive exceeds capture bound")
            entries.append((member, relative))
        require(any(relative.as_posix() == "manifest.json" for _, relative in entries), "final manifest missing; export is partial")
        output.mkdir(parents=True)
        for member, relative in entries:
            target = output.joinpath(*relative.parts)
            require(target.resolve().is_relative_to(output), "archive escapes output")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open("xb") as destination:
                    shutil.copyfileobj(source, destination)
    return output


def adb_path(value):
    if value:
        return str(value)
    found = shutil.which("adb")
    if found:
        return found
    return str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/platform-tools/adb.exe")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", type=Path)
    parser.add_argument("--serial")
    parser.add_argument("--recording")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--receipt", type=Path, help="optional small JSON receipt; never contains raw media")
    args = parser.parse_args()
    receipt = {"schema": "bagdar-native-capture-export-v1", "deviceRuntime": "not_run",
               "promotionAllowed": False, "safetyReplayReady": False}
    status = 2
    try:
        require(bool(args.recording) == bool(args.output), "export requires both --recording and --output")
        if args.recording:
            require(ID.fullmatch(args.recording), "invalid recording ID")
            output = checked_output(args.output)
            if args.receipt:
                require(not args.receipt.resolve().is_relative_to(output), "export receipt must be outside the raw recording directory")
        adb = adb_path(args.adb)
        result = subprocess.run([adb, "devices", "-l"], check=True, capture_output=True, text=True, timeout=15)
        devices = [line.split()[0] for line in result.stdout.splitlines() if re.match(r"^\S+\s+device(?:\s|$)", line)]
        receipt["attachedAuthorizedDeviceCount"] = len(devices)
        require(devices, "no attached authorized Android device")
        serial = args.serial or (devices[0] if len(devices) == 1 else None)
        require(serial in devices, "select exactly one attached device with --serial")
        require(not serial.startswith("emulator-"), "capture protocol requires a physical phone")
        command = [adb, "-s", serial]
        qemu = subprocess.run(command + ["shell", "getprop", "ro.kernel.qemu"], check=True,
                              capture_output=True, text=True, timeout=15).stdout.strip()
        require(qemu != "1", "capture protocol requires a physical phone")
        if not args.recording:
            result = subprocess.run(command + ["shell", "run-as", PACKAGE, "ls", "files/research-captures"],
                                    check=True, capture_output=True, text=True, timeout=15)
            receipt.update(deviceRuntime="capture_metadata_only", recordings=[line for line in result.stdout.splitlines() if ID.fullmatch(line)])
            status = 0
        else:
            with tempfile.TemporaryDirectory(prefix="bagdar-capture-export-") as temporary:
                archive = Path(temporary) / "capture.tar"
                with archive.open("wb") as stream:
                    subprocess.run(command + ["exec-out", "run-as", PACKAGE, "tar", "-C", "files/research-captures",
                                              "-cf", "-", args.recording], stdout=stream, stderr=subprocess.PIPE,
                                   check=True, timeout=30)
                require(archive.stat().st_size <= MAX_BYTES + 4 * 1024 * 1024, "archive too large")
                output = unpack(archive, args.recording, args.output)
            review = audit(output, expected_recording_id=args.recording)
            (output / "audit.json").write_text(json.dumps(review, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            receipt.update(deviceRuntime="capture_export_only", recordingId=args.recording,
                           outputLocationRedacted=True, integrityPassed=review["integrityPassed"],
                           finalizedNonemptyCapture=review["finalizedNonemptyCapture"], sameFrameCandidates=review["sameFrameCandidates"],
                           recordingSelectionMatched=review["recordingSelectionMatched"])
            status = 0 if review["finalizedNonemptyCapture"] else 2
    except (CaptureError, OSError, ValueError, subprocess.SubprocessError, tarfile.TarError, KeyError, TypeError, AttributeError) as error:
        receipt["error"] = str(error)
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2, ensure_ascii=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
