from __future__ import annotations
import os
from typing import Tuple
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

class LLMEnv(BaseSettings):
    # gpt_client.py -> services -> app -> server -> .env
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[2] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )
    OPENAI_API_KEY: str | None = None

def _fallback_score_and_feedback(metrics: dict, transcript: str) -> Tuple[float, str]:
    # 간단 폴백: 규칙 점수 보정 + 짧은 피드백
    rule = float(metrics.get("rule_score", 0.0))
    bonus = 5.0 if metrics.get("filler_density", 0) < 3 else -5.0
    score = max(0.0, min(100.0, rule * 0.9 + bonus))
    fb = (
        "자동 생성 피드백(LLM 미사용): 전반적으로 이해 가능한 발화예요. "
        "필러를 조금만 더 줄이고, 핵심 문장을 더 짧게 말해보세요."
    )
    return score, fb

def get_llm_score_and_feedback(metrics: dict, transcript: str) -> Tuple[float, str]:
    """
    OPENAI_API_KEY가 없거나 실패 시 폴백을 반환.
    """
    # .env 우선, 없으면 OS 환경변수 사용
    api_key = LLMEnv().OPENAI_API_KEY or os.getenv("OPENAI_API_KEY")
    if not api_key:
        return _fallback_score_and_feedback(metrics, transcript)

    try:
        # OpenAI SDK v1 계열 예시
        from openai import OpenAI  # type: ignore
        client = OpenAI(api_key=api_key)

        prompt = (
            "You are an English speaking coach. Evaluate the learner's spoken English "
            "quality on a 0-100 scale (higher is better). Consider the given metrics, "
            "but also judge coherence, grammar, vocabulary, and pronunciation from the transcript. "
            "Return JSON: {\"score\": number, \"feedback\": string}.\n\n"
            f"Metrics: {metrics}\nTranscript:\n{transcript}"
        )
        resp = client.chat.completions.create(
            model="gpt-5-nano",
            messages=[
                {"role": "system", "content": "당신은 영어 학습 코치입니다. 모든 피드백은 한국어로만 작성하고, JSON의 feedback 값도 한국어로 작성하세요."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.3,
        )
        content = resp.choices[0].message.content or ""
        # 매우 관대한 파서 (JSON 한 줄이 아닐 수 있음)
        import json, re
        json_str = re.search(r"\{.*\}", content, re.S)
        if json_str:
            data = json.loads(json_str.group(0))
            score = float(data.get("score", 0.0))
            feedback = str(data.get("feedback", "")).strip()
            if 0 <= score <= 100 and feedback:
                return score, feedback

        # 파싱 실패 시 폴백
        return _fallback_score_and_feedback(metrics, transcript)
    except Exception:
        return _fallback_score_and_feedback(metrics, transcript)
