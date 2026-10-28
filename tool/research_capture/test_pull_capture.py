import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from audit_capture import CaptureError
from pull_capture import unpack, checked_output, REPO

ID = "capture-00000000-0000-0000-0000-000000000001"


class CaptureExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / "capture.tar"
        self.output = self.root / "export"

    def archive_with(self, names, link=None):
        with tarfile.open(self.archive, "w") as archive:
            for name in names:
                member = tarfile.TarInfo(name)
                member.size = 2
                archive.addfile(member, io.BytesIO(b"{}"))
            if link:
                member = tarfile.TarInfo(f"{ID}/payloads/link.bin")
                member.type = tarfile.SYMTYPE
                member.linkname = link
                archive.addfile(member)

    def test_normal_archive_keeps_bytes_under_new_output(self):
        self.archive_with([f"{ID}/manifest.json", f"{ID}/frames.jsonl", f"{ID}/payloads/0000-depth-0.bin"])
        unpack(self.archive, ID, self.output)
        self.assertEqual((self.output / "payloads/0000-depth-0.bin").read_bytes(), b"{}")

    def test_traversal_rejected_before_any_file_written(self):
        self.archive_with([f"{ID}/manifest.json", f"{ID}/../../escape.bin"])
        with self.assertRaisesRegex(CaptureError, "escapes"):
            unpack(self.archive, ID, self.output)
        self.assertFalse(self.output.exists())

    def test_symlink_rejected_before_any_file_written(self):
        self.archive_with([f"{ID}/manifest.json"], link="../../secret")
        with self.assertRaisesRegex(CaptureError, "links"):
            unpack(self.archive, ID, self.output)
        self.assertFalse(self.output.exists())

    def test_duplicate_payloads_rejected_before_any_file_written(self):
        self.archive_with([f"{ID}/manifest.json", f"{ID}/manifest.json"])
        with self.assertRaisesRegex(CaptureError, "duplicate"):
            unpack(self.archive, ID, self.output)

    def test_existing_output_never_overwritten(self):
        self.output.mkdir()
        (self.output / "keep.txt").write_text("keep")
        with self.assertRaisesRegex(CaptureError, "exists"):
            checked_output(self.output)
        self.assertEqual((self.output / "keep.txt").read_text(), "keep")

    def test_raw_media_cannot_go_to_this_or_another_git_repository(self):
        with self.assertRaisesRegex(CaptureError, "outside"):
            checked_output(REPO / "scratch/raw-media")
        (self.root / ".git").mkdir()
        with self.assertRaisesRegex(CaptureError, "Git checkout"):
            checked_output(self.output)

    def test_partial_archive_without_final_manifest_rejected(self):
        self.archive_with([f"{ID}/pending.json", f"{ID}/frames.jsonl"])
        with self.assertRaisesRegex(CaptureError, "partial"):
            unpack(self.archive, ID, self.output)


if __name__ == "__main__":
    unittest.main()
