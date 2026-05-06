from __future__ import annotations
import json, re
from pathlib import Path
from typing import Iterable, List, Dict, Set

_TAGS_PATH = Path(__file__).resolve().parents[2] / "config" / "dictionaries" / "error_tags.json"

class TagNormalizer:
    def __init__(self, path=_TAGS_PATH):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        self.canonical: Set[str] = set(data["canonical_tags"])
        self.aliases: Dict[str, str] = {k.lower(): v for k, v in data["aliases"].items()}

    def normalize_one(self, t: str) -> str | None:
        if not t: return None
        key = re.sub(r"\s+", "_", t.strip().lower())
        if key in self.canonical: return key
        return self.aliases.get(key)

    def normalize(self, tags: Iterable[str]) -> List[str]:
        out = []
        for t in tags:
            n = self.normalize_one(t)
            if n and n not in out:
                out.append(n)
        return out