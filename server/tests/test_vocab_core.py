import json
import unittest
from pathlib import Path

from app.services.vocab_srs import GRADE_TO_QUALITY, _adj_ease


class VocabCoreTests(unittest.TestCase):
    def test_grade_mapping(self):
        self.assertEqual(GRADE_TO_QUALITY["again"], 1)
        self.assertEqual(GRADE_TO_QUALITY["hard"], 3)
        self.assertEqual(GRADE_TO_QUALITY["good"], 4)
        self.assertEqual(GRADE_TO_QUALITY["easy"], 5)

    def test_adj_ease_bounds(self):
        self.assertGreaterEqual(_adj_ease(1.0, 0), 1.3)
        self.assertLessEqual(_adj_ease(4.0, 5), 3.5)

    def test_seed_file_shape(self):
        seed_path = Path(__file__).resolve().parents[1] / "dictionaries" / "vocab_seed.json"
        self.assertTrue(seed_path.exists())
        data = json.loads(seed_path.read_text(encoding="utf-8"))
        self.assertIsInstance(data, list)
        self.assertGreaterEqual(len(data), 600)
        first = data[0]
        self.assertIn("lemma", first)
        self.assertIn("meaning_ko", first)
        self.assertIn("difficulty", first)
        counts = {1: 0, 2: 0, 3: 0}
        for item in data:
            d = int(item.get("difficulty", 0))
            if d in counts:
                counts[d] += 1
            self.assertEqual(item.get("category"), "toeic")
        self.assertGreaterEqual(counts[1], 200)
        self.assertGreaterEqual(counts[2], 200)
        self.assertGreaterEqual(counts[3], 200)


if __name__ == "__main__":
    unittest.main()
