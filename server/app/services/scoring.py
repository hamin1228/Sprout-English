# FILE: english_ai/server/app/services/scoring.py
from __future__ import annotations
import math
import re
from typing import Dict, Any
from app.schemas import Metrics, SubScores

FILLERS = [
    "um", "uh", "erm", "mm", "ah", "uhh", "hmm",
    "like", "you know", "kind of", "sort of", "actually", "basically"
]

def _count_words(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))

def _count_fillers(text: str) -> int:
    t = text.lower()
    count = 0
    for f in FILLERS:
        if " " in f:
            count += len(re.findall(rf"\b{re.escape(f)}\b", t))
        else:
            count += len(re.findall(rf"\b{re.escape(f)}\b", t))
    return count

def compute_metrics(transcript: str, duration_ms: int, silence_ms: int | None) -> Metrics:
    words = _count_words(transcript)
    minutes = max(duration_ms / 60000.0, 1e-6)
    wpm = words / minutes
    silence_ratio = max(0.0, min(1.0, (silence_ms or 0) / duration_ms))
    filler_count = _count_fillers(transcript)
    return Metrics(words=words, wpm=wpm, filler_count=filler_count, silence_ratio=silence_ratio)

def _score_wpm(wpm: float) -> float:
    # 130 wpm = 100점, 70/200에서 0점, 선형 클램프
    if wpm <= 70 or wpm >= 200:
        return 0.0
    if wpm <= 130:
        return (wpm - 70) / (130 - 70) * 100
    return (200 - wpm) / (200 - 130) * 100

def _penalty_fillers(filler_per_100w: float) -> float:
    # 100단어당 필러 0개=0감점, 10개=최대 40감점, 선형
    return min(40.0, max(0.0, (filler_per_100w / 10.0) * 40.0))

def _penalty_silence(r: float) -> float:
    # 침묵비 0~30% → 0~25 감점, 30% 초과 고정 25
    return min(25.0, r / 0.30 * 25.0)

def rule_subscores(m: Metrics) -> SubScores:
    wpm_score = _score_wpm(m.wpm)
    filler_per_100w = (m.filler_count / max(m.words, 1)) * 100
    filler_penalty = _penalty_fillers(filler_per_100w)
    silence_penalty = _penalty_silence(m.silence_ratio)
    rule_score = max(0.0, min(100.0, wpm_score - filler_penalty - silence_penalty))
    return SubScores(
        wpm_score=wpm_score,
        filler_penalty=filler_penalty,
        silence_penalty=silence_penalty,
        rule_score=rule_score,
        gpt_score=0.0,  # 나중에 채움
    )

def merge_scores(rule_score: float, gpt_score: float, rule_weight: float = 0.6) -> float:
    lw = 1.0 - rule_weight
    return round(rule_weight * rule_score + lw * gpt_score, 1)