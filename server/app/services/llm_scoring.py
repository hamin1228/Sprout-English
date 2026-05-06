# FILE: english_ai/server/app/services/llm_scoring.py
from __future__ import annotations
from typing import Dict, Any
from app.schemas import Metrics

# TODO: GPT-5 연결시 여기 구현. 현재는 간단한 휴리스틱/템플릿 기반 피드백.
def evaluate_with_llm_stub(metrics: Metrics, transcript: str) -> tuple[float, dict]:
    # 규칙 점수 보정용 부가점: 어휘 다양성/문장 길이 등 간단 추정
    unique_words = len(set(w.lower() for w in transcript.split()))
    diversity = unique_words / max(metrics.words, 1)
    llm_score = max(0.0, min(100.0, 50 + (diversity - 0.5) * 80))  # 50±(대략)40

    tips = []
    if metrics.wpm < 90:
        tips.append("조금 더 또렷하고 빠르게 말해 보세요 (목표 120~150 wpm).")
    if metrics.filler_count > 0:
        tips.append("‘um/uh/like’ 같은 필러를 줄이기 위해 문장 시작 전에 0.5초 숨 고르기.")
    if metrics.silence_ratio > 0.2:
        tips.append("긴 침묵을 줄이려면 말할 포인트를 2~3개 메모하고 이어서 말해요.")
    if diversity < 0.45:
        tips.append("동일 어휘 반복을 줄이고 동의어를 섞어 사용해 보세요.")

    feedback = {
        "summary": "자동 피드백(LLM 대체 스텁)",
        "suggestions": tips or ["전반적으로 안정적이에요. 더 길게 말해보며 표현을 넓혀보세요!"],
        "metrics_snapshot": metrics.model_dump(),
    }
    return float(round(llm_score, 1)), feedback