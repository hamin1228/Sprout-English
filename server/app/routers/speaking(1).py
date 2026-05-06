# FILE: english_ai/server/app/routers/speaking.py
from __future__ import annotations
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import SpeakingScore
from app.schemas import ScoreRequest, ScoreResponse, SpeakingScoreRead, SpeakingScoreList, Metrics
from app.services.scoring import compute_metrics, rule_subscores, merge_scores
from app.services.llm_scoring import evaluate_with_llm_stub

router = APIRouter(prefix="/speaking", tags=["speaking"])

@router.post("/score", response_model=ScoreResponse)
async def speaking_score(payload: ScoreRequest, session: AsyncSession = Depends(get_session)):
    m: Metrics = compute_metrics(payload.transcript, payload.duration_ms, payload.silence_ms)
    subs = rule_subscores(m)
    gpt_score, feedback = evaluate_with_llm_stub(m, payload.transcript)
    subs.gpt_score = gpt_score
    total = merge_scores(subs.rule_score, subs.gpt_score, rule_weight=0.6)

    if payload.store:
        rec = SpeakingScore(
            user_id=payload.user_id,
            session_id=payload.session_id,
            transcript=payload.transcript,
            duration_ms=payload.duration_ms,
            words=m.words,
            wpm=m.wpm,
            filler_count=m.filler_count,
            silence_ratio=m.silence_ratio,
            rule_score=subs.rule_score,
            gpt_score=subs.gpt_score,
            total_score=total,
            feedback=feedback,
        )
        session.add(rec)
        await session.commit()

    return ScoreResponse(
        total_score=total,
        metrics=m,
        subscores=subs,
        feedback=feedback,
    )

@router.get("/scores/{score_id}", response_model=SpeakingScoreRead)
async def get_score(score_id: int, session: AsyncSession = Depends(get_session)):
    rec = await session.get(SpeakingScore, score_id)
    if not rec:
        raise HTTPException(status_code=404, detail="score not found")
    return rec

@router.get("/scores", response_model=SpeakingScoreList)
async def list_scores(
    user_id: str = Query(...),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    session: AsyncSession = Depends(get_session),
):
    total = (await session.execute(select(func.count()).select_from(SpeakingScore).where(SpeakingScore.user_id == user_id))).scalar_one()
    rows = (
        await session.execute(
            select(SpeakingScore)
            .where(SpeakingScore.user_id == user_id)
            .order_by(SpeakingScore.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
    ).scalars().all()
    return SpeakingScoreList(items=rows, total=total)

@router.delete("/scores/{score_id}")
async def delete_score(score_id: int, session: AsyncSession = Depends(get_session)):
    res = await session.execute(delete(SpeakingScore).where(SpeakingScore.id == score_id))
    await session.commit()
    if res.rowcount == 0:
        raise HTTPException(status_code=404, detail="score not found")
    return {"ok": True, "deleted": score_id}