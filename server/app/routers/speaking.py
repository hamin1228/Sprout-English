from __future__ import annotations

import json
import os
import re
import time
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, HTTPException, Query

from app.core.logging import log
from app.core.openai_clients import get_sync_client

router = APIRouter()

# ── /speaking/score ─────────────────────────────────────────────────────────

_DEFAULT_FILLERS = [
    "um", "uh", "er", "erm", "hmm", "you know", "like", "so", "actually",
    "basically", "right", "i mean", "well",
]


def _count_words(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))


def _count_fillers(text: str, fillers: List[str]) -> int:
    t = " " + re.sub(r"\s+", " ", text.lower()) + " "
    return sum(len(re.findall(r"\b" + re.escape(f) + r"\b", t)) for f in fillers)


def _score_wpm(wpm: float) -> float:
    if wpm <= 60 or wpm >= 220:
        return 0.0
    if wpm <= 140:
        return (wpm - 60) / (140 - 60) * 100
    return (220 - wpm) / (220 - 140) * 100


def _score_silence_ratio(ratio: float) -> float:
    if ratio <= 0.10:
        return 100.0
    if ratio >= 0.40:
        return 0.0
    return (0.40 - ratio) / (0.40 - 0.10) * 100


def _score_filler_density(per_100w: float) -> float:
    if per_100w <= 2.0:
        return 100.0
    if per_100w >= 10.0:
        return 0.0
    return (10.0 - per_100w) / (10.0 - 2.0) * 100


@router.post("/speaking/score")
async def speaking_score(
    payload: dict = Body(...),
    save: bool = Query(False),
):
    transcript = str(payload.get("transcript", "")).strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="transcript is required")

    duration_ms = max(1, int(payload.get("duration_ms", 0)))
    silence_ms_total = int(payload.get("silence_ms_total", 0))
    filler_override = payload.get("filler_words_override") or []
    words = _count_words(transcript)
    fillers = [w.lower().strip() for w in (filler_override if isinstance(filler_override, list) else [])] or _DEFAULT_FILLERS
    filler_count = _count_fillers(transcript, fillers)

    minutes = duration_ms / 1000 / 60
    wpm = words / minutes if minutes > 0 else 0.0
    silence_ratio = silence_ms_total / duration_ms if duration_ms > 0 else 0.0
    filler_density = (filler_count / max(1, words)) * 100.0
    sw = _score_wpm(wpm)
    ss = _score_silence_ratio(silence_ratio)
    sf = _score_filler_density(filler_density)
    rule_score = round(0.4 * sw + 0.3 * ss + 0.3 * sf, 2)

    metrics: Dict[str, Any] = {
        "words": words,
        "wpm": round(wpm, 2),
        "silence_ms_total": int(silence_ms_total),
        "silence_ratio": round(silence_ratio, 4),
        "filler_count": int(filler_count),
        "filler_density": round(filler_density, 2),
        "subscores": {"wpm": round(sw, 2), "silence": round(ss, 2), "filler": round(sf, 2)},
        "rule_score": rule_score,
    }

    llm_score = None
    feedback = None
    try:
        from app.services.gpt_client import get_llm_score_and_feedback  # type: ignore
        if callable(get_llm_score_and_feedback):
            llm_score, feedback = get_llm_score_and_feedback(metrics, transcript)
    except Exception:
        pass

    final_score = round(0.6 * rule_score + 0.4 * float(llm_score), 2) if llm_score is not None else rule_score

    return {
        "id": None,
        "transcript": transcript,
        **{k: v for k, v in metrics.items() if k != "subscores"},
        "rule_subscores": metrics["subscores"],
        "llm_score": llm_score,
        "final_score": final_score,
        "feedback": feedback,
    }


# ── /speaking/free-talk/score ────────────────────────────────────────────────

_FREE_TALK_SCORE_TABLE: Dict[str, List[int]] = {
    "task_fulfillment_interaction": [0, 9, 15, 21, 26, 30],
    "pronunciation_delivery":       [0, 6, 10, 14, 17, 20],
    "fluency":                      [0, 6, 10, 14, 17, 20],
    "grammar_control":              [0, 5,  8, 11, 13, 15],
    "vocabulary_expression":        [0, 5,  8, 11, 13, 15],
}

_FREE_TALK_DIMENSION_ORDER = [
    "task_fulfillment_interaction",
    "pronunciation_delivery",
    "fluency",
    "grammar_control",
    "vocabulary_expression",
]

_FREE_TALK_NEXT_ACTIONS = {
    "task_fulfillment_interaction": "질문에 답한 뒤 이유나 예시를 한 문장 더 붙여 대화를 조금 더 확장해 보세요.",
    "pronunciation_delivery": "짧은 핵심 문장을 천천히 또렷하게 읽고 바로 따라 말하는 연습으로 전달력을 높여보세요.",
    "fluency": "답변 시작 전에 연결 표현을 하나 정해 두고 말해 불필요한 멈춤을 줄여보세요.",
    "grammar_control": "자주 쓰는 문장 패턴 2~3개를 통째로 반복해 문법 안정감을 먼저 확보해 보세요.",
    "vocabulary_expression": "같은 뜻을 다른 표현으로 바꿔 말하는 연습을 추가해 표현 범위를 넓혀보세요.",
}

_FREE_TALK_SYSTEM_PROMPT = """You are an expert evaluator for English speaking performance in a language-learning app.
Return valid JSON only. Do not wrap the JSON in markdown.

Evaluation dimensions and weights:
1) Task Fulfillment & Interaction: 30 points
2) Pronunciation & Delivery Clarity: 20 points
3) Fluency: 20 points
4) Grammar Control: 15 points
5) Vocabulary & Expressive Range: 15 points

Score caps:
- Task Fulfillment level 0 → total cap 19
- Task Fulfillment level 1 → total cap 49
- Task Fulfillment level 2 → total cap 69
- Level 3+ → no cap

Return JSON: {"version":"speaking_rubric_v1","task_id":"...","scores":{...},"total_score":0,"overall_summary":"...","next_actions":["...","..."],"diagnostics":{"applied_total_score_cap":null,"confidence":0.0}}"""


def _safe_int(value: Any, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(round(value))
    try:
        return int(str(value).strip())
    except Exception:
        return default


def _safe_float(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip())
    except Exception:
        return default


def _clip_level(level: Any) -> int:
    return max(0, min(5, _safe_int(level)))


def _count_english_words(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))


def _extract_json_object(raw: str) -> Dict[str, Any]:
    raw = (raw or "").strip()
    if not raw:
        raise ValueError("empty_response")
    try:
        return json.loads(raw)
    except Exception:
        match = re.search(r"\{.*\}", raw, re.S)
        if not match:
            raise
        return json.loads(match.group(0))


def _score_from_level(key: str, level: int) -> int:
    return _FREE_TALK_SCORE_TABLE[key][_clip_level(level)]


def _total_score_cap(task_level: int) -> Optional[int]:
    return {0: 19, 1: 49, 2: 69}.get(task_level)


def _normalize_actions(actions: Any, scores: Dict[str, Dict[str, Any]]) -> List[str]:
    normalized = [str(a).strip() for a in (actions if isinstance(actions, list) else []) if str(a).strip()]
    if len(normalized) >= 2:
        return normalized[:2]
    weakest = sorted(_FREE_TALK_DIMENSION_ORDER, key=lambda k: (scores[k]["score"], scores[k]["level"]))
    for key in weakest:
        suggestion = _FREE_TALK_NEXT_ACTIONS[key]
        if suggestion not in normalized:
            normalized.append(suggestion)
        if len(normalized) == 2:
            break
    while len(normalized) < 2:
        normalized.append("짧게 말한 뒤 한 문장을 더 덧붙이는 연습으로 답변 확장력을 키워보세요.")
    return normalized[:2]


def _normalize_free_talk_result(result: Dict[str, Any], payload: Dict[str, Any]) -> Dict[str, Any]:
    task = payload.get("task") if isinstance(payload.get("task"), dict) else {}
    scores_in = result.get("scores") if isinstance(result.get("scores"), dict) else {}
    normalized_scores: Dict[str, Dict[str, Any]] = {}
    score_sum = 0
    for key in _FREE_TALK_DIMENSION_ORDER:
        raw_item = scores_in.get(key) if isinstance(scores_in.get(key), dict) else {}
        level = _clip_level(raw_item.get("level"))
        score = _score_from_level(key, level)
        normalized_scores[key] = {
            "level": level,
            "score": score,
            "evidence": str(raw_item.get("evidence") or "제공된 대화 기록을 기준으로 판단했습니다."),
            "feedback": str(raw_item.get("feedback") or "다음 대화에서는 문장을 조금 더 안정적으로 확장해 보세요."),
        }
        score_sum += score
    task_level = normalized_scores["task_fulfillment_interaction"]["level"]
    applied_cap = _total_score_cap(task_level)
    total_score = min(score_sum, applied_cap) if applied_cap is not None else score_sum
    diagnostics_in = result.get("diagnostics") if isinstance(result.get("diagnostics"), dict) else {}
    confidence = max(0.0, min(1.0, _safe_float(diagnostics_in.get("confidence"), 0.65)))
    return {
        "version": "speaking_rubric_v1",
        "task_id": str(result.get("task_id") or task.get("task_id") or "free_talk"),
        "scores": normalized_scores,
        "total_score": total_score,
        "overall_summary": str(result.get("overall_summary") or "대화 흐름과 문장 확장 정도를 기준으로 프리토킹 수행을 종합 평가했습니다."),
        "next_actions": _normalize_actions(result.get("next_actions"), normalized_scores),
        "diagnostics": {"applied_total_score_cap": applied_cap, "confidence": round(confidence, 2)},
    }


def _fallback_free_talk_score(payload: Dict[str, Any]) -> Dict[str, Any]:
    task = payload.get("task") if isinstance(payload.get("task"), dict) else {}
    response = payload.get("response") if isinstance(payload.get("response"), dict) else {}
    speech = payload.get("speech_features") if isinstance(payload.get("speech_features"), dict) else {}
    transcript = str(response.get("transcript") or "").strip()
    turns = response.get("turns") if isinstance(response.get("turns"), list) else []
    user_turns = [str(t.get("text") or "").strip() for t in turns if isinstance(t, dict) and str(t.get("speaker") or "").lower() == "user" and str(t.get("text") or "").strip()]
    partner_turns = [str(t.get("text") or "").strip() for t in turns if isinstance(t, dict) and str(t.get("speaker") or "").lower() != "user" and str(t.get("text") or "").strip()]
    user_turn_count = max(_safe_int(speech.get("user_turn_count")), len(user_turns))
    words = _count_english_words(transcript)
    unique_words = len(set(re.findall(r"[A-Za-z']+", transcript.lower())))
    total_user_duration_ms = _safe_int(speech.get("total_user_duration_ms"))
    speech_rate_wpm = _safe_float(speech.get("speech_rate_wpm"))
    if speech_rate_wpm <= 0 and total_user_duration_ms > 0:
        speech_rate_wpm = words / max(total_user_duration_ms / 60000, 0.01)
    pause_count = _safe_int(speech.get("pause_count"), -1)
    long_pause_count = _safe_int(speech.get("long_pause_count"), -1)
    intelligibility = _safe_float(speech.get("pronunciation_intelligibility_estimate"), -1)
    avg_words_per_turn = words / max(user_turn_count, 1)
    type_token_ratio = unique_words / max(words, 1)
    response_ratio = min(1.0, user_turn_count / max(len(partner_turns), 1)) if partner_turns else (1.0 if user_turn_count > 0 else 0.0)
    pause_burden = 0.0
    if pause_count >= 0:
        pause_burden += pause_count / max(user_turn_count, 1)
    if long_pause_count >= 0:
        pause_burden += long_pause_count * 1.5 / max(user_turn_count, 1)

    if words < 4 or user_turn_count == 0:
        task_level = 0
    elif user_turn_count == 1 or words < 12:
        task_level = 2
    elif response_ratio >= 0.9 and user_turn_count >= 3 and avg_words_per_turn >= 8:
        task_level = 4
    else:
        task_level = 3

    if intelligibility >= 0.9:
        pron_level = 5
    elif intelligibility >= 0.82:
        pron_level = 4
    elif intelligibility >= 0.72:
        pron_level = 3
    elif intelligibility >= 0.6:
        pron_level = 2
    elif intelligibility >= 0:
        pron_level = 1
    elif words >= 20 and user_turn_count >= 2:
        pron_level = 3
    elif words >= 8:
        pron_level = 2
    else:
        pron_level = 1

    if words < 4:
        fluency_level = 0
    elif 85 <= speech_rate_wpm <= 150 and pause_burden <= 2.5:
        fluency_level = 4
    elif 70 <= speech_rate_wpm <= 170:
        fluency_level = 3
    elif speech_rate_wpm > 0:
        fluency_level = 2
    else:
        fluency_level = 1

    grammar_markers = len(re.findall(r"\b(because|if|when|but|so|that)\b", transcript.lower()))
    if words < 5:
        grammar_level = 0
    elif avg_words_per_turn >= 8 and grammar_markers >= 1:
        grammar_level = 4
    elif avg_words_per_turn >= 5:
        grammar_level = 3
    else:
        grammar_level = 2

    if words < 5:
        vocab_level = 0
    elif unique_words >= 30 and type_token_ratio >= 0.55:
        vocab_level = 4
    elif unique_words >= 15 and type_token_ratio >= 0.4:
        vocab_level = 3
    else:
        vocab_level = 2

    scores: Dict[str, Dict[str, Any]] = {
        "task_fulfillment_interaction": {
            "level": task_level, "score": _score_from_level("task_fulfillment_interaction", task_level),
            "evidence": f"사용자 발화 {user_turn_count}회, 총 {words}단어 기준으로 질문에 반응하며 대화를 이어간 정도를 평가했습니다.",
            "feedback": "답변 뒤에 이유나 예시를 한 문장 더 붙이면 상호작용 점수를 더 끌어올릴 수 있습니다.",
        },
        "pronunciation_delivery": {
            "level": pron_level, "score": _score_from_level("pronunciation_delivery", pron_level),
            "evidence": (f"제공된 intelligibility 추정치 {intelligibility:.2f}를 반영했습니다." if intelligibility >= 0 else "오디오 기반 발음 평가는 없어서 전사 안정성과 대화 지속 여부를 기준으로 보수적으로 평가했습니다."),
            "feedback": "짧은 핵심 문장을 천천히 또렷하게 반복해서 말하면 전달 명료도를 높이는 데 도움이 됩니다.",
        },
        "fluency": {
            "level": fluency_level, "score": _score_from_level("fluency", fluency_level),
            "evidence": f"말하기 속도는 약 {speech_rate_wpm:.1f} WPM이며, 제공된 멈춤 정보와 턴 길이를 함께 봤습니다.",
            "feedback": "답변 시작 전에 연결 표현을 정해 두고 말하면 불필요한 멈춤을 줄일 수 있습니다.",
        },
        "grammar_control": {
            "level": grammar_level, "score": _score_from_level("grammar_control", grammar_level),
            "evidence": f"턴당 평균 {avg_words_per_turn:.1f}단어와 문장 연결 표현 사용 정도를 바탕으로 문장 안정성을 평가했습니다.",
            "feedback": "자주 쓰는 문장 패턴을 통째로 반복해 두면 문법 정확성을 더 안정적으로 유지할 수 있습니다.",
        },
        "vocabulary_expression": {
            "level": vocab_level, "score": _score_from_level("vocabulary_expression", vocab_level),
            "evidence": f"고유 어휘 {unique_words}개, type-token ratio {type_token_ratio:.2f} 기준으로 표현 다양성을 평가했습니다.",
            "feedback": "같은 의미를 다른 표현으로 바꿔 말하는 연습을 추가하면 어휘 및 표현 범위가 넓어집니다.",
        },
    }
    total = sum(item["score"] for item in scores.values())
    confidence = 0.55
    if user_turn_count >= 3:
        confidence += 0.1
    if total_user_duration_ms >= 30000:
        confidence += 0.1
    if intelligibility >= 0:
        confidence += 0.1
    if pause_count >= 0:
        confidence += 0.05
    weakest = sorted(_FREE_TALK_DIMENSION_ORDER, key=lambda k: scores[k]["score"])
    return {
        "version": "speaking_rubric_v1",
        "task_id": str(task.get("task_id") or "free_talk"),
        "scores": scores,
        "total_score": total,
        "overall_summary": "대화를 유지하는 능력은 확인됐고, 더 높은 점수를 위해서는 답변 확장과 말하기 안정감을 함께 끌어올리는 것이 중요합니다.",
        "next_actions": [_FREE_TALK_NEXT_ACTIONS[weakest[0]], _FREE_TALK_NEXT_ACTIONS[weakest[1 if len(weakest) > 1 else 0]]],
        "diagnostics": {"applied_total_score_cap": _total_score_cap(task_level), "confidence": min(confidence, 0.9)},
    }


def _llm_free_talk_score(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    try:
        client = get_sync_client()
        model = os.getenv("OPENAI_SCORING_MODEL") or "gpt-5-nano"
        resp = client.chat.completions.create(
            model=model,
            temperature=0.2,
            messages=[
                {"role": "system", "content": _FREE_TALK_SYSTEM_PROMPT},
                {"role": "user", "content": "Evaluate the following learner conversation payload.\n" + json.dumps(payload, ensure_ascii=False)},
            ],
        )
        content = resp.choices[0].message.content or ""
        return _extract_json_object(content)
    except Exception as e:
        log.warning(f"LLM free-talk scoring failed: {e}", trace_id="-")
        return None


@router.post("/speaking/free-talk/score")
async def speaking_free_talk_score(payload: dict = Body(...)):
    task = payload.get("task") if isinstance(payload.get("task"), dict) else {}
    response = payload.get("response") if isinstance(payload.get("response"), dict) else {}
    transcript = str(response.get("transcript") or "").strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="response.transcript is required")
    if not task.get("task_id"):
        payload.setdefault("task", {})
        payload["task"]["task_id"] = f"free_talk_{int(time.time())}"
    scored = _llm_free_talk_score(payload) or _fallback_free_talk_score(payload)
    return _normalize_free_talk_result(scored, payload)
