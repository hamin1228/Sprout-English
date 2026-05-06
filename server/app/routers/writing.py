from __future__ import annotations
import json
import re
import random
from pathlib import Path
from typing import Any, List, Optional
import os

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, false
from sqlalchemy.orm import noload
from sqlalchemy.ext.asyncio import AsyncSession
from openai import OpenAI

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from app.db import get_session
from app.db import SessionLocal
from app import models
from app.schemas import (
    WritingEvalRequest, WritingEvalResponse, Edit,
    CreateScoreRequest, WritingScoreResponse as ScoreResponse, ListScoresResponse, UpdateScoreRequest,
    ToeicWritingEvalRequest, ToeicWritingEvalResponse, ToeicWritingPromptResponse,
    ToeicWritingTaskType, ToeicWritingLevel, ToeicRubricItem,
)

router = APIRouter(prefix="/writing", tags=["writing"])
client: Optional[OpenAI] = None
_toeic_prompt_bank: Optional[list[dict[str, Any]]] = None

def _get_client() -> OpenAI:
    global client
    if client is None:
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set on the server")
        client = OpenAI(api_key=api_key, timeout=30.0, max_retries=0)
    return client

GUIDANCE_VERSION = "writing_eval_v1_20251011"
MODEL_NAME = "gpt-5-nano"
TOEIC_GUIDANCE_VERSION = "toeic_writing_eval_v2_20260321"

def _normalize_text(t: str) -> str:
    t = t.replace("\u00a0", " ").replace("\u2019", "'").replace("\u201c", '"').replace("\u201d", '"')
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\s+\n", "\n", t).strip()
    return t

SYSTEM_PROMPT = """You are an English writing evaluator for Korean college students.
Return STRICT JSON only (no prose). Avoid over-correction:
- Do NOT change meaning or tone.
- Prefer comments when multiple valid phrasings exist.
- Keep idioms and proper nouns unless incorrect.
Output schema:
{
  "normalized_text": str,
  "edits": [ { "kind": "replace|insert|delete|comment", "start": int, "end": int, "replacement": str|null, "reason": str, "category": "grammar|word_choice|style|punctuation|fluency|register|other", "severity": "minor|moderate|major" } ],
  "checklist": [str],
  "warnings": [str],
  "score": int (0-100)
}
Rules for indices: 'start' and 'end' are zero-based character offsets on normalized_text, end-exclusive.
Limit edits to what is necessary for clarity and correctness.
"""

def _extract_json(s: str) -> dict:
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        m = re.search(r"```json\s*(\{.*?\})\s*```", s, re.DOTALL)
        if m:
            try:
                return json.loads(m.group(1))
            except json.JSONDecodeError as e:
                raise ValueError(f"Failed to decode fenced JSON: {e}")
        raise ValueError("Failed to extract JSON from the model's response.")

async def _call_llm(payload: dict) -> dict:
    user_msg = json.dumps(payload, ensure_ascii=False)
    cli = _get_client()
    try:
        r = cli.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_msg},
            ],
            response_format={"type": "json_object"},
            timeout=30,
        )
        txt = r.choices[0].message.content or "{}"
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI model service unavailable: {e}")
    try:
        data = _extract_json(txt)
        return data
    except ValueError as e:
        raise HTTPException(status_code=500, detail=f"Failed to parse AI model's JSON response: {e}")

def _coerce_edits(edits_raw: list[dict]) -> list[Edit]:
    coerced: list[Edit] = []
    if not isinstance(edits_raw, list):
        return []
    for e in edits_raw:
        try:
            coerced.append(Edit(**e))
        except Exception:
            e.setdefault("kind", "comment")
            e.setdefault("start", 0)
            e.setdefault("end", 0)
            e.setdefault("reason", "unspecified (schema error)")
            e.setdefault("replacement", None)
            e.setdefault("category", "other")
            e.setdefault("severity", "minor")
            coerced.append(Edit(**e))
    return coerced

# --- JSON coercion helpers (DB JSON may arrive as str/obj) ---
def _as_list(v):
    if v is None:
        return []
    if isinstance(v, str):
        try:
            v = json.loads(v)
        except Exception:
            return []
    return v if isinstance(v, list) else []

def _as_edits(v):
    # Accept str (JSON), dict with {edits: [...]}, or list
    if isinstance(v, str):
        try:
            v = json.loads(v)
        except Exception:
            v = []
    if isinstance(v, dict):
        v = v.get("edits", [])
    if not isinstance(v, list):
        v = []
    return _coerce_edits(v)

def _row_to_score_response(row: models.WritingScore) -> ScoreResponse:
    edits_list = _as_edits(row.result_edits)
    checklist = _as_list(row.result_checklist)
    warnings = _as_list(row.result_warnings)
    # created_at / updated_at can be datetime or string depending on driver; normalize to str
    created = row.created_at.isoformat() if hasattr(row.created_at, "isoformat") else str(row.created_at)
    updated = row.updated_at.isoformat() if hasattr(row.updated_at, "isoformat") else str(row.updated_at)
    return ScoreResponse(
        id=row.id,
        user_id=row.user_id,
        input_text=row.input_text,
        normalized_text=row.normalized_text,
        edits=edits_list,
        checklist=checklist,
        warnings=warnings,
        score=row.score,
        model_name=row.model_name,
        guidance_version=row.guidance_version,
        notes=row.notes,
        created_at=created,
        updated_at=updated,
        is_deleted=row.is_deleted,
    )

@router.post("/eval", response_model=WritingEvalResponse)
async def eval_writing(req: WritingEvalRequest, session: AsyncSession = Depends(get_session)) -> WritingEvalResponse:
    normalized = _normalize_text(req.text)
    llm_in = {"text": normalized, "level": req.level, "task": req.task, "audience": req.audience, "style": req.style, "guidance_version": GUIDANCE_VERSION}
    data = await _call_llm(llm_in)
    
    normalized_text = data.get("normalized_text", normalized)
    edits = _coerce_edits(data.get("edits", []))
    checklist = data.get("checklist", [])
    warnings = data.get("warnings", [])
    score = int(data.get("score", 0))
    record_id: Optional[int] = None

    if req.save:
        obj = models.WritingScore(
            user_id=req.user_id, input_text=req.text, normalized_text=normalized_text,
            result_edits=[e.model_dump() for e in edits], result_checklist=checklist,
            result_warnings=warnings, score=score, model_name=MODEL_NAME, guidance_version=GUIDANCE_VERSION,
        )
        session.add(obj)
        await session.flush()
        
        session.add(models.WritingScoreAudit(
            score_id=obj.id, action="create",
            snapshot={k: getattr(obj, k) for k in ["input_text", "normalized_text", "result_edits", "result_checklist", "result_warnings", "score", "model_name", "guidance_version"]}
        ))
        await session.commit()
        await session.refresh(obj)
        record_id = obj.id

    return WritingEvalResponse(
        normalized_text=normalized_text, edits=edits, checklist=checklist,
        warnings=warnings, score=score, guidance_version=GUIDANCE_VERSION,
        model_name=MODEL_NAME, record_id=record_id
    )

@router.post("/scores", response_model=ScoreResponse)
async def create_score(req: CreateScoreRequest, session: AsyncSession = Depends(get_session)) -> ScoreResponse:
    obj = models.WritingScore(
        user_id=req.user_id, input_text=req.input_text, normalized_text=req.normalized_text,
        result_edits=[e.model_dump() for e in req.edits], result_checklist=req.checklist,
        result_warnings=req.warnings, score=req.score, model_name=req.model_name,
        guidance_version=req.guidance_version, notes=req.notes,
    )
    session.add(obj)
    await session.flush()
    session.add(models.WritingScoreAudit(
        score_id=obj.id, action="create",
        snapshot={k: getattr(obj, k) for k in ["input_text", "normalized_text", "result_edits", "result_checklist", "result_warnings", "score", "model_name", "guidance_version", "notes"]}
    ))
    await session.commit()
    await session.refresh(obj)
    try:
        return _row_to_score_response(obj)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"serialize error: {e}")

@router.get("/scores", response_model=ListScoresResponse)
async def list_scores(
    session: AsyncSession = Depends(get_session), user_id: Optional[str] = None,
    include_deleted: bool = False, limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0),
) -> ListScoresResponse:
    conds = []
    if not include_deleted:
        conds.append(models.WritingScore.is_deleted.is_(false()))
    if user_id:
        conds.append(models.WritingScore.user_id == user_id)

    stmt = select(models.WritingScore).options(noload(models.WritingScore.audits)).where(*conds).order_by(models.WritingScore.id.desc()).limit(limit).offset(offset)
    result = await session.execute(stmt)
    rows = result.scalars().all()

    count_stmt = select(func.count()).select_from(models.WritingScore).where(*conds)
    total_result = await session.execute(count_stmt)
    total = total_result.scalar_one()

    items = [_row_to_score_response(r) for r in rows]
    next_offset = offset + limit if offset + limit < total else None
    return ListScoresResponse(items=items, next_offset=next_offset, total=total)

@router.get("/scores/{score_id}", response_model=ScoreResponse)
async def get_score(score_id: int, session: AsyncSession = Depends(get_session)) -> ScoreResponse:
    row = await session.get(models.WritingScore, score_id, options=[noload(models.WritingScore.audits)])
    if not row or row.is_deleted:
        raise HTTPException(status_code=404, detail="Score not found")
    return _row_to_score_response(row)

@router.patch("/scores/{score_id}", response_model=ScoreResponse)
async def update_score(score_id: int, req: UpdateScoreRequest, session: AsyncSession = Depends(get_session)) -> ScoreResponse:
    row = await session.get(models.WritingScore, score_id, options=[noload(models.WritingScore.audits)])
    if not row or row.is_deleted:
        raise HTTPException(status_code=404, detail="Score not found")

    session.add(models.WritingScoreAudit(
        score_id=row.id, action="update",
        snapshot={"before": {"score": row.score, "notes": row.notes}, "patch": req.model_dump(exclude_unset=True)}
    ))
    
    update_data = req.model_dump(exclude_unset=True)
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")

    for key, value in update_data.items():
        setattr(row, key, value)

    await session.commit()
    await session.refresh(row)
    return _row_to_score_response(row)

@router.delete("/scores/{score_id}", status_code=200)
async def delete_score(score_id: int, session: AsyncSession = Depends(get_session)) -> dict:
    row = await session.get(models.WritingScore, score_id, options=[noload(models.WritingScore.audits)])
    if not row or row.is_deleted:
        raise HTTPException(status_code=404, detail="Score not found")
        
    row.is_deleted = True
    session.add(models.WritingScoreAudit(
        score_id=row.id, action="delete", snapshot={"deleted": True}
    ))
    await session.commit()
    return {"ok": True, "deleted_id": score_id}


def _load_toeic_prompt_bank() -> list[dict[str, Any]]:
    global _toeic_prompt_bank
    if _toeic_prompt_bank is None:
        bank_path = Path(__file__).resolve().parents[2] / "dictionaries" / "toeic_writing_prompts.json"
        with bank_path.open("r", encoding="utf-8") as fp:
            _toeic_prompt_bank = json.load(fp)
    return _toeic_prompt_bank


def _public_prompt_payload(prompt: dict[str, Any]) -> ToeicWritingPromptResponse:
    image_asset = prompt.get("image_asset")
    if isinstance(image_asset, str) and "assets/toeic_writing_images/" in image_asset and image_asset.endswith(".png"):
        image_asset = f"{image_asset[:-4]}.jpg"

    return ToeicWritingPromptResponse(
        prompt_id=str(prompt["prompt_id"]),
        task_type=prompt["task_type"],
        title=str(prompt["title"]),
        instructions=str(prompt["instructions"]),
        time_limit_sec=int(prompt["time_limit_sec"]),
        recommended_words=int(prompt["recommended_words"]),
        required_points=[str(item) for item in prompt.get("required_points", [])],
        image_asset=image_asset,
        source_text=prompt.get("source_text"),
        keywords=prompt.get("keywords"),
    )


def _find_prompt(prompt_id: str) -> dict[str, Any]:
    for prompt in _load_toeic_prompt_bank():
        if prompt.get("prompt_id") == prompt_id:
            return prompt
    raise HTTPException(status_code=404, detail="TOEIC writing prompt not found")


def _count_words(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))


def _has_terminal_punctuation(text: str) -> bool:
    return text.rstrip().endswith((".", "!", "?"))


def _sentence_chunks(text: str) -> list[str]:
    chunks = [part.strip() for part in re.split(r"(?<=[.!?])\s+", text.strip()) if part.strip()]
    return chunks


def _text_corrections(text: str, *, expect_email: bool = False) -> list[str]:
    corrections: list[str] = []
    stripped = text.strip()
    if stripped and stripped[0].islower():
        corrections.append("첫 문장의 시작은 대문자로 쓰는 편이 자연스럽습니다.")
    if stripped and not _has_terminal_punctuation(stripped):
        corrections.append("마지막 문장 끝에 마침표를 넣어 문장을 마무리하세요.")
    if expect_email:
        lowered = stripped.lower()
        if not any(token in lowered for token in ("dear", "hello", "hi")):
            corrections.append("이메일 답장에는 간단한 인사말을 포함하면 톤이 더 자연스럽습니다.")
        if not any(token in lowered for token in ("best", "regards", "sincerely", "thank you")):
            corrections.append("마무리 문구를 넣으면 이메일 형식이 더 안정적입니다.")
    return corrections


def _score_text_form(text: str) -> tuple[int, list[str]]:
    corrections = _text_corrections(text)
    score = 30
    if corrections:
        score -= min(12, len(corrections) * 6)
    chunks = _sentence_chunks(text)
    if len(chunks) < 3:
        corrections.append("문장을 3개 이상으로 나누면 구조가 더 분명해집니다.")
        score -= 6
    unique_words = {w.lower() for w in re.findall(r"[A-Za-z']+", text)}
    if len(unique_words) < 25:
        corrections.append("같은 단어 반복을 줄이고 표현을 조금 더 다양하게 써보세요.")
        score -= 4
    return max(10, score), corrections


def _toeic_rubric_spec(task_type: ToeicWritingTaskType) -> list[dict[str, Any]]:
    if task_type == "picture":
        return [
            {"label": "내용 일치", "max_score": 30},
            {"label": "핵심 요소 포함", "max_score": 30},
            {"label": "표현 자연스러움", "max_score": 20},
            {"label": "문법 정확성", "max_score": 20},
        ]
    if task_type == "email":
        return [
            {"label": "요청 충족", "max_score": 35},
            {"label": "톤/격식", "max_score": 20},
            {"label": "구성", "max_score": 20},
            {"label": "문법/어휘", "max_score": 25},
        ]
    return [
        {"label": "입장 명확성", "max_score": 25},
        {"label": "근거/전개", "max_score": 30},
        {"label": "구성", "max_score": 20},
        {"label": "문법/어휘", "max_score": 25},
    ]


TOEIC_COMPARE_SYSTEM_PROMPT = """You are a TOEIC Writing evaluator.
Compare the learner response against the task, the required points, and the reference answer.
The learner may use different wording and still deserve a high score if the meaning, task completion, and logic are strong.
Explain all feedback in Korean. Return STRICT JSON only with this schema:
{
  "overall_score": int,
  "rubric": [
    {"label": str, "score": int, "max_score": int, "feedback": str}
  ],
  "content_analysis": [str],
  "grammar_feedback": [str],
  "matched_points": [str],
  "missing_points": [str],
  "better_answer_tips": [str]
}
Rules:
- Score based on meaning and task fulfillment, not surface similarity.
- A different but valid expression should still score well.
- Only list missing_points when a required idea is absent or clearly contradicted.
- grammar_feedback must focus on real grammar or expression issues and stay concise.
- content_analysis should explain why the answer is strong or weak.
- better_answer_tips should be concrete and actionable.
- Keep overall_score aligned with the rubric sum.
"""


def _fallback_toeic_eval(prompt: dict[str, Any], text: str, task_type: ToeicWritingTaskType) -> ToeicWritingEvalResponse:
    stripped = text.strip()
    if not stripped:
        raise HTTPException(status_code=400, detail="Submission text is required")

    required_points = [str(item) for item in prompt.get("required_points", [])]
    lowered = stripped.lower()
    matched_points: list[str] = []
    missing_points: list[str] = []

    for point in required_points:
        significant_words = [
            token for token in re.findall(r"[A-Za-z']+", point.lower())
            if len(token) > 3 and token not in {"look", "write", "clear", "main", "with", "that", "this", "your", "have", "from"}
        ]
        if significant_words and any(word in lowered for word in significant_words):
            matched_points.append(point)
        else:
            missing_points.append(point)

    form_score, form_corrections = _score_text_form(stripped)
    rubric_spec = _toeic_rubric_spec(task_type)
    coverage_ratio = (len(matched_points) / max(1, len(required_points)))
    if task_type == "picture":
        scores = [
            round(coverage_ratio * 30),
            round(coverage_ratio * 30),
            min(20, round((form_score / 30) * 20)),
            min(20, round((form_score / 30) * 20)),
        ]
    elif task_type == "email":
        tone_bonus = 1.0 if any(token in lowered for token in ("please", "could", "would", "thank you", "best", "regards")) else 0.6
        scores = [
            round(coverage_ratio * 35),
            round(20 * tone_bonus),
            20 if len(_sentence_chunks(stripped)) >= 3 else 14,
            min(25, round((form_score / 30) * 25)),
        ]
    else:
        support_bonus = 1.0 if any(token in lowered for token in ("because", "for example", "first", "second", "in addition", "overall")) else 0.6
        scores = [
            round(coverage_ratio * 25),
            round(30 * support_bonus),
            20 if len(_sentence_chunks(stripped)) >= 3 else 14,
            min(25, round((form_score / 30) * 25)),
        ]

    rubric = [
        ToeicRubricItem(
            label=spec["label"],
            score=max(0, min(spec["max_score"], score)),
            max_score=spec["max_score"],
            feedback="핵심 포인트 반영도와 문장 완성도를 기준으로 평가했습니다.",
        )
        for spec, score in zip(rubric_spec, scores)
    ]
    overall = sum(item.score for item in rubric)
    content_analysis = [
        "모범답안과 표현이 달라도 핵심 내용이 맞으면 정답으로 인정하는 방식으로 평가했습니다.",
        "핵심 포인트를 많이 반영할수록 높은 점수를 받습니다." if matched_points else "핵심 포인트가 직접적으로 드러나지 않아 감점되었습니다.",
    ]
    grammar_feedback = form_corrections or ["문법상 큰 문제는 두드러지지 않습니다."]
    better_answer_tips = [
        "모범답안을 그대로 외우기보다 required points를 빠짐없이 담는 데 집중하세요.",
        "문장 첫 글자 대문자와 문장부호를 먼저 점검하면 기본 점수를 안정적으로 확보할 수 있습니다.",
    ]
    return ToeicWritingEvalResponse(
        overall_score=overall,
        rubric=rubric,
        model_answer=str(prompt["model_answer"]),
        content_analysis=content_analysis,
        grammar_feedback=grammar_feedback,
        matched_points=matched_points,
        missing_points=missing_points,
        better_answer_tips=better_answer_tips,
    )


def _coerce_toeic_eval_response(
    raw: dict[str, Any],
    *,
    prompt: dict[str, Any],
    task_type: ToeicWritingTaskType,
) -> ToeicWritingEvalResponse:
    rubric_spec = _toeic_rubric_spec(task_type)
    rubric_raw = raw.get("rubric", [])
    rubric: list[ToeicRubricItem] = []

    for index, spec in enumerate(rubric_spec):
        item = rubric_raw[index] if isinstance(rubric_raw, list) and index < len(rubric_raw) and isinstance(rubric_raw[index], dict) else {}
        try:
            score = int(item.get("score", 0))
        except Exception:
            score = 0
        rubric.append(
            ToeicRubricItem(
                label=spec["label"],
                score=max(0, min(spec["max_score"], score)),
                max_score=spec["max_score"],
                feedback=str(item.get("feedback", "세부 코멘트가 제공되지 않았습니다.")),
            )
        )

    overall = sum(item.score for item in rubric)
    return ToeicWritingEvalResponse(
        overall_score=max(0, min(100, overall)),
        rubric=rubric,
        model_answer=str(prompt["model_answer"]),
        content_analysis=[str(item) for item in raw.get("content_analysis", []) if str(item).strip()],
        grammar_feedback=[str(item) for item in raw.get("grammar_feedback", []) if str(item).strip()],
        matched_points=[str(item) for item in raw.get("matched_points", []) if str(item).strip()],
        missing_points=[str(item) for item in raw.get("missing_points", []) if str(item).strip()],
        better_answer_tips=[str(item) for item in raw.get("better_answer_tips", []) if str(item).strip()],
    )


def _score_toeic_with_llm(prompt: dict[str, Any], text: str, task_type: ToeicWritingTaskType) -> ToeicWritingEvalResponse:
    stripped = text.strip()
    if not stripped:
        raise HTTPException(status_code=400, detail="Submission text is required")

    payload = {
        "guidance_version": TOEIC_GUIDANCE_VERSION,
        "task_type": task_type,
        "title": prompt.get("title"),
        "instructions": prompt.get("instructions"),
        "required_points": prompt.get("required_points", []),
        "source_text": prompt.get("source_text"),
        "reference_answer": prompt.get("model_answer"),
        "learner_submission": stripped,
        "rubric_spec": _toeic_rubric_spec(task_type),
    }
    cli = _get_client()
    try:
        result = cli.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": TOEIC_COMPARE_SYSTEM_PROMPT},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
            ],
            response_format={"type": "json_object"},
            timeout=30,
        )
        raw = _extract_json(result.choices[0].message.content or "{}")
        response = _coerce_toeic_eval_response(raw, prompt=prompt, task_type=task_type)
        if not response.content_analysis:
            response.content_analysis = ["제출한 답안의 핵심 포인트 반영 여부를 기준으로 비교 평가했습니다."]
        if not response.grammar_feedback:
            response.grammar_feedback = ["문법상 큰 문제는 두드러지지 않습니다."]
        if not response.better_answer_tips:
            response.better_answer_tips = ["required points를 먼저 체크한 뒤 문장을 다듬어 제출하세요."]
        return response
    except Exception:
        return _fallback_toeic_eval(prompt, stripped, task_type)


@router.get("/toeic/prompt", response_model=ToeicWritingPromptResponse)
async def get_toeic_writing_prompt(
    task_type: ToeicWritingTaskType = Query(...),
    level: ToeicWritingLevel = Query("beginner"),
) -> ToeicWritingPromptResponse:
    candidates = [
        prompt for prompt in _load_toeic_prompt_bank()
        if prompt.get("task_type") == task_type and prompt.get("level") == level
    ]
    if not candidates:
        raise HTTPException(status_code=404, detail="No TOEIC writing prompt available for the requested type")
    return _public_prompt_payload(random.choice(candidates))


@router.post("/toeic/eval", response_model=ToeicWritingEvalResponse)
async def eval_toeic_writing(
    req: ToeicWritingEvalRequest,
) -> ToeicWritingEvalResponse:
    prompt = _find_prompt(req.prompt_id)
    if prompt.get("task_type") != req.task_type:
        raise HTTPException(status_code=400, detail="Prompt type and submission type do not match")

    submission_text = (req.submission.text or "").strip()
    response = _score_toeic_with_llm(prompt, submission_text, req.task_type)
    submission_payload: dict[str, Any] = {
        "text": submission_text,
        "analysis": {
            "content_analysis": response.content_analysis,
            "grammar_feedback": response.grammar_feedback,
            "matched_points": response.matched_points,
            "missing_points": response.missing_points,
            "better_answer_tips": response.better_answer_tips,
            "guidance_version": TOEIC_GUIDANCE_VERSION,
        },
    }

    if req.save:
        try:
            async with SessionLocal() as session:
                record = models.ToeicWritingScore(
                    user_id=req.user_id,
                    task_type=req.task_type,
                    prompt_id=str(prompt["prompt_id"]),
                    prompt_meta=_public_prompt_payload(prompt).model_dump(),
                    submission=submission_payload,
                    rubric=[item.model_dump() for item in response.rubric],
                    overall_score=response.overall_score,
                    model_answer=response.model_answer,
                    sentence_feedback=response.grammar_feedback,
                    corrections=response.content_analysis,
                    checklist=[
                        *[f"반영됨: {item}" for item in response.matched_points],
                        *[f"보완 필요: {item}" for item in response.missing_points],
                    ],
                    next_actions=response.better_answer_tips,
                )
                session.add(record)
                await session.commit()
                await session.refresh(record)
                response.record_id = record.id
        except Exception as exc:
            raise HTTPException(
                status_code=503,
                detail=f"평가는 완료되었지만 결과 저장에 실패했습니다: {exc}",
            ) from exc

    return response
