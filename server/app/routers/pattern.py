from __future__ import annotations

from fastapi import APIRouter

from app.schemas import (
    ParaphraseRequest,
    ParaphraseResponse,
    PatternDrillGenerateResponse,
    PatternDrillRequest,
    PatternDrillScoreResponse,
)
from app.services import llm
from app.services.eval import score_answer

router = APIRouter()


def _pattern_drill(req: PatternDrillRequest):
    if req.task == "generate":
        if llm.is_llm_available():
            system = open("config/prompts/pattern_drill_v1.md", "r", encoding="utf-8").read()
            user = f"pattern: {req.pattern}\ncontext: {req.context or '-'}\ncount: {req.count}\nReturn JSON following the contract.\n"
            data = llm.chat_json(system, user, temperature=0.4)
            if data and "items" in data:
                return PatternDrillGenerateResponse(items=data["items"])
        base = [
            {"prompt": f"Use '{req.pattern}' to invite a friend politely.", "answers": ["Would you like to join us?", "Would you like to come along?"]},
            {"prompt": f"Use '{req.pattern}' to ask for directions.", "answers": ["Would you like to tell me the way?", "Would you mind showing me the route?"]},
            {"prompt": f"Use '{req.pattern}' to offer help.", "answers": ["Would you like some help with that?", "Would you like me to assist you?"]},
        ]
        import random
        items = (base * ((req.count // len(base)) + 1))[: req.count]
        random.shuffle(items)
        return PatternDrillGenerateResponse(items=items)

    if req.task == "score":
        user_answer = (req.user_answer or "").strip()
        if not user_answer:
            return PatternDrillScoreResponse(score=0.0, passed=False, feedback="Answer is required.")
        tolerance = req.tolerance if req.tolerance is not None else 0.70
        result = score_answer(user_answer, req.reference_answers or [], tolerance=tolerance)
        return PatternDrillScoreResponse(
            score=result["score"],
            passed=result["passed"],
            feedback=result.get("feedback", ""),
        )

    return PatternDrillGenerateResponse(items=[])


def _paraphrase(req: ParaphraseRequest):
    tone = req.tone or "neutral"
    length = req.length or "same"
    n = req.n or 3

    if llm.is_llm_available():
        system = "You are a paraphrase assistant. Return only a JSON array of paraphrased strings. No markdown, no explanation."
        user = f'Paraphrase the following text {n} times. Tone: {tone}. Length: {length}.\nText: "{req.text}"\nReturn format: ["...","..."]'
        raw = llm.chat_json(system, user, temperature=0.7)
        if isinstance(raw, list):
            variants = [str(x) for x in raw[:n]]
        elif isinstance(raw, dict) and "variants" in raw:
            variants = [str(x) for x in raw["variants"][:n]]
        else:
            variants = [req.text]
    else:
        variants = [
            f"[{tone}] " + req.text,
            req.text + " (paraphrase)",
            "In other words, " + req.text.lower(),
        ][:n]

    return ParaphraseResponse(variants=variants, tone=tone, length=length)


@router.post("/pattern/drill")
def pattern_drill_api(req: PatternDrillRequest):
    return _pattern_drill(req)


@router.post("/paraphrase")
def paraphrase_api(req: ParaphraseRequest):
    return _paraphrase(req)
