from __future__ import annotations

import json
import unittest
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROMPT_BANK_PATH = ROOT / "server" / "dictionaries" / "toeic_writing_prompts.json"


class ToeicPromptBankTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.prompt_bank = json.loads(PROMPT_BANK_PATH.read_text(encoding="utf-8"))

    def test_prompt_counts_by_type_and_level(self) -> None:
        by_type = Counter()
        by_level = defaultdict(Counter)

        for item in self.prompt_bank:
            by_type[item["task_type"]] += 1
            by_level[item["task_type"]][item["level"]] += 1

        self.assertEqual(by_type["picture"], 150)
        self.assertEqual(by_type["email"], 150)
        self.assertEqual(by_type["opinion"], 150)

        for task_type in ("picture", "email", "opinion"):
            for level in ("beginner", "intermediate", "advanced"):
                self.assertEqual(by_level[task_type][level], 50)

    def test_picture_prompts_have_unique_remote_urls(self) -> None:
        picture_prompts = [item for item in self.prompt_bank if item["task_type"] == "picture"]
        seen_assets: set[str] = set()

        for item in picture_prompts:
            asset = item.get("image_asset")
            self.assertTrue(asset, msg=f"missing image asset for {item['prompt_id']}")
            self.assertNotIn(asset, seen_assets, msg=f"duplicate asset mapping for {asset}")
            seen_assets.add(asset)
            self.assertTrue(str(asset).startswith("http"), msg=f"picture prompt does not use remote URL: {asset}")

    def test_all_prompts_have_model_answers_and_required_points(self) -> None:
        for item in self.prompt_bank:
            self.assertTrue(str(item.get("model_answer", "")).strip(), msg=item["prompt_id"])
            self.assertGreaterEqual(len(item.get("required_points", [])), 3, msg=item["prompt_id"])


if __name__ == "__main__":
    unittest.main()
