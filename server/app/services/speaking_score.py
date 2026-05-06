# server/app/services/speaking_score.py
from __future__ import annotations
import json, re
from pathlib import Path
from typing import Tuple, List

DEFAULT_FILLERS = [
    "um", "uh", "er", "erm", "hmm", "you know", "like", "so", "actually",
    "basically", "right", "i mean", "well"
]

def load_fillers(project_root: Path, override: List[str] | None) -> List[str]:
    if override:
        return [w.lower().strip() for w in override if w.strip()]
    cfg = project_root / "dictionaries" / "custom_words.json"
    if cfg.exists():
        try:
            data = json.loads(cfg.read_text(encoding="utf-8"))
            words = data.get("fillers", [])
            if isinstance(words, list) and words:
                return [w.lower().strip() for w in words]
        except Exception:
            pass
    return DEFAULT_FILLERS

_word_re = re.compile(r"[A-Za-z']+")

def count_words(text: str) -> int:
    return len(_word_re.findall(text))

def count_fillers(text: str, fillers: List[str]) -> int:
    t = " " + re.sub(r"\s+", " ", text.lower()) + " "
    count = 0
    for f in fillers:
        # 단어 경계 유사 매칭
        pattern = r"\b" + re.escape(f) + r"\b"
        count += len(re.findall(pattern, t))
    return count

def score_wpm(wpm: float) -> float:
    # 120~160 wpm 최적, 140 정점 삼각함수형 스코어
    if wpm <= 60 or wpm >= 220:
        return 0.0
    # 상승: 60→140, 하강: 140→220
    if wpm <= 140:
        return (wpm - 60) / (140 - 60) * 100
    return (220 - wpm) / (220 - 140) * 100

def score_silence_ratio(ratio: float) -> float:
    # <=0.10 → 100, >=0.40 → 0, 선형 보간
    if ratio <= 0.10:
        return 100.0
    if ratio >= 0.40:
        return 0.0
    return (0.40 - ratio) / (0.40 - 0.10) * 100

def score_filler_density(per_100w: float) -> float:
    # <=2/100 → 100, >=10/100 → 0, 선형 보간
    if per_100w <= 2.0:
        return 100.0
    if per_100w >= 10.0:
        return 0.0
    return (10.0 - per_100w) / (10.0 - 2.0) * 100

def rule_based_score(words: int, duration_ms: int, silence_ms_total: int, filler_count: int) -> Tuple[dict, float]:
    duration_ms = max(1, int(duration_ms))
    minutes = duration_ms / 1000 / 60
    wpm = words / minutes if minutes > 0 else 0.0
    silence_ratio = (silence_ms_total / duration_ms) if duration_ms > 0 else 0.0
    filler_density = (filler_count / max(1, words)) * 100.0 * 1.0  # per 100 words

    sw = score_wpm(wpm)
    ss = score_silence_ratio(silence_ratio)
    sf = score_filler_density(filler_density)

    rule = 0.4 * sw + 0.3 * ss + 0.3 * sf
    metrics = {
        "words": words,
        "wpm": round(wpm, 2),
        "silence_ms_total": int(silence_ms_total),
        "silence_ratio": round(silence_ratio, 4),
        "filler_count": int(filler_count),
        "filler_density": round(filler_density, 2),
        "subscores": {"wpm": round(sw, 2), "silence": round(ss, 2), "filler": round(sf, 2)},
        "rule_score": round(rule, 2),
    }
    return metrics, rule

def combine_scores(rule_score: float, llm_score: float | None) -> float:
    if llm_score is None:
        return round(rule_score, 2)
    return round(0.6 * rule_score + 0.4 * llm_score, 2)