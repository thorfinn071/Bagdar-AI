"""Corpus-level checks for the temporal Blender benchmark."""

from __future__ import annotations

import unittest

import numpy as np
from PIL import Image

from evaluate_blender_detectors import REPO_ROOT
from evaluate_temporal_blender import load_sequences


class TemporalBlenderContractTest(unittest.TestCase):
    def test_context_coco_labels_are_explicit_and_scorable(self) -> None:
        labels = (REPO_ROOT / "assets/labels.txt").read_text(encoding="utf-8").splitlines()
        self.assertEqual([labels[index] for index in (0, 1, 28)], ["person", "bicycle", "suitcase"])
        _, sequences = load_sequences("blender-context-v3")
        expected = {
            "context-low-obstacle": [28],
            "context-crossing-rider": [0, 1],
        }
        for sequence in sequences:
            for frame in sequence["frames"]:
                self.assertEqual(
                    frame["compatibleCocoClassIds"],
                    expected.get(sequence["sceneId"], []),
                )

    def test_every_hazard_is_visible_in_each_distinct_frame(self) -> None:
        for corpus_id, prefix in (
            ("blender-temporal-v2", "temporal"),
            ("blender-context-v3", "context"),
        ):
            with self.subTest(corpus_id=corpus_id):
                _, sequences = load_sequences(corpus_id)
                self.assertEqual(len(sequences), 6)
                self.assertEqual(sum(len(sequence["frames"]) for sequence in sequences), 18)
                hazards = {
                    f"{prefix}-thin-pole": 2,
                    f"{prefix}-low-obstacle": 4,
                    f"{prefix}-overhead": 5,
                    f"{prefix}-crossing-rider": 10,
                }
                for sequence in sequences:
                    hashes = {frame["rgbSha256"] for frame in sequence["frames"]}
                    self.assertEqual(len(hashes), 3, sequence["sceneId"])
                    if sequence["sceneId"] not in hazards:
                        continue
                    for frame in sequence["frames"]:
                        with Image.open(frame["semanticPath"]) as source:
                            mask = np.asarray(source, dtype=np.uint8)
                        center = mask[:, mask.shape[1] // 3:mask.shape[1] * 2 // 3]
                        self.assertGreaterEqual(
                            int((center == hazards[sequence["sceneId"]]).sum()),
                            1000 if corpus_id == "blender-context-v3" else 8,
                            f"{sequence['sceneId']} frame {frame['frameIndex']}",
                        )


if __name__ == "__main__":
    unittest.main()
