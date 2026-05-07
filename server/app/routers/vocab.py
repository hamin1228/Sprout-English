from __future__ import annotations

import json
import random
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config_loader import settings
from app.db import get_session
from app.models import VocabCard, VocabSRSState
from app.schemas import (
    VocabCardCreate,
    VocabCardOut,
    VocabCardUpdate,
    VocabImportRequest,
    VocabImportResult,
    VocabLevel,
    VocabMCQItem,
    VocabReviewIn,
    VocabReviewOut,
    VocabSRSItem,
)
from app.services.vocab_srs import apply_vocab_review, ensure_vocab_state

router = APIRouter()

_vocab_seed_path = Path(__file__).resolve().parents[2] / "dictionaries" / "vocab_seed.json"
_vocab_again_queue: deque[int] = deque(maxlen=200)
_vocab_mcq_recent: dict[str, deque[int]] = {
    "beginner": deque(maxlen=60),
    "intermediate": deque(maxlen=60),
    "advanced": deque(maxlen=60),
}


def _direction_by_difficulty(difficulty: int) -> str:
    if difficulty <= 1:
        return "word_to_meaning"
    if difficulty == 2:
        return "meaning_to_word"
    return random.choice(["word_to_meaning", "meaning_to_word"])


def _difficulty_by_level(level: str) -> int:
    return {"beginner": 1, "intermediate": 2, "advanced": 3}[level]


def _level_by_difficulty(difficulty: int) -> str:
    if difficulty <= 1:
        return "beginner"
    if difficulty == 2:
        return "intermediate"
    return "advanced"


def _pick_unique_choices(correct: str, distractors: list[str]) -> tuple[list[str], int]:
    seen: set[str] = {correct}
    unique: list[str] = []
    for d in distractors:
        if d not in seen and len(unique) < 3:
            seen.add(d)
            unique.append(d)
    while len(unique) < 3:
        unique.append(f"(option {len(unique) + 1})")
    pool = unique[:3] + [correct]
    random.shuffle(pool)
    return pool, pool.index(correct)


def _load_vocab_seed() -> list[dict[str, Any]]:
    try:
        return json.loads(_vocab_seed_path.read_text(encoding="utf-8"))
    except Exception:
        return []


async def _ensure_vocab_catalog(db: AsyncSession, min_per_level: int = 200) -> int:
    total = await db.scalar(select(func.count(VocabCard.id)))
    if (total or 0) >= min_per_level * 3:
        return int(total or 0)
    seed = _load_vocab_seed()
    imported = 0
    for item in seed:
        lemma = str(item.get("lemma", "")).strip()
        meaning_ko = str(item.get("meaning_ko", "")).strip()
        if not lemma or not meaning_ko:
            continue
        exists = await db.scalar(
            select(VocabCard).where(VocabCard.lemma == lemma, VocabCard.meaning_ko == meaning_ko, VocabCard.source == "builtin")
        )
        if exists:
            continue
        card = VocabCard(
            user_id="system",
            lemma=lemma,
            meaning_ko=meaning_ko,
            example_en=(str(item.get("example_en", "")).strip()) or None,
            difficulty=int(item.get("difficulty", 1)),
            source="builtin",
            tags=str(item.get("tags", "")).strip() or None,
            pos=str(item.get("pos", "")).strip() or None,
        )
        db.add(card)
        await db.flush()
        await ensure_vocab_state(db, card.id)
        imported += 1
    if imported > 0:
        await db.commit()
    total_after = await db.scalar(select(func.count(VocabCard.id)))
    return int(total_after or 0)


# ── CRUD ─────────────────────────────────────────────────────────────────────

@router.post("/vocab/cards", response_model=VocabCardOut)
async def create_vocab_card(payload: VocabCardCreate, db: AsyncSession = Depends(get_session)):
    card = VocabCard(
        user_id=payload.user_id,
        lemma=payload.lemma.strip(),
        meaning_ko=payload.meaning_ko.strip(),
        example_en=(payload.example_en or "").strip() or None,
        difficulty=payload.difficulty,
        source="manual",
        tags=(payload.tags or "").strip() or None,
        pos=(payload.pos or "").strip() or None,
    )
    db.add(card)
    await db.flush()
    await ensure_vocab_state(db, card.id)
    await db.commit()
    await db.refresh(card)
    return card


@router.get("/vocab/cards", response_model=list[VocabCardOut])
async def list_vocab_cards(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_session),
):
    q = await db.execute(select(VocabCard).order_by(VocabCard.id.desc()).offset(offset).limit(limit))
    return q.scalars().all()


@router.get("/vocab/cards/{card_id}", response_model=VocabCardOut)
async def get_vocab_card(card_id: int, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    return card


@router.patch("/vocab/cards/{card_id}", response_model=VocabCardOut)
async def update_vocab_card(card_id: int, payload: VocabCardUpdate, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        if isinstance(value, str):
            value = value.strip() or None
        setattr(card, key, value)
    await db.commit()
    await db.refresh(card)
    return card


@router.delete("/vocab/cards/{card_id}")
async def delete_vocab_card(card_id: int, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    await db.delete(card)
    await db.commit()
    return {"ok": True, "card_id": card_id}


@router.post("/vocab/cards/import", response_model=VocabImportResult)
async def import_vocab_cards(payload: VocabImportRequest, db: AsyncSession = Depends(get_session)):
    candidates = _load_vocab_seed()
    if payload.level:
        wanted_difficulty = _difficulty_by_level(payload.level)
        candidates = [x for x in candidates if int(x.get("difficulty", wanted_difficulty)) == wanted_difficulty]
    if payload.category:
        category = payload.category.strip().lower()
        candidates = [x for x in candidates if str(x.get("category", "")).strip().lower() == category]
    candidates = candidates[: payload.limit]

    imported = 0
    skipped = 0
    for item in candidates:
        lemma = str(item.get("lemma", "")).strip()
        meaning_ko = str(item.get("meaning_ko", "")).strip()
        if not lemma or not meaning_ko:
            skipped += 1
            continue
        exists = await db.scalar(
            select(VocabCard).where(VocabCard.lemma == lemma, VocabCard.meaning_ko == meaning_ko, VocabCard.source == "builtin")
        )
        if exists:
            skipped += 1
            continue
        card = VocabCard(
            user_id="system",
            lemma=lemma,
            meaning_ko=meaning_ko,
            example_en=str(item.get("example_en", "")).strip() or None,
            difficulty=int(item.get("difficulty", 1)),
            source="builtin",
            tags=str(item.get("tags", "")).strip() or None,
            pos=str(item.get("pos", "")).strip() or None,
        )
        db.add(card)
        await db.flush()
        await ensure_vocab_state(db, card.id)
        imported += 1
    if imported > 0:
        await db.commit()
    total_after = await db.scalar(select(func.count(VocabCard.id)))
    return VocabImportResult(imported=imported, skipped=skipped, total=int(total_after or 0))


# ── SRS ──────────────────────────────────────────────────────────────────────

@router.get("/vocab/srs/next", response_model=list[VocabSRSItem])
async def vocab_srs_next(
    limit: int = Query(20, ge=1, le=100),
    level: Optional[VocabLevel] = Query(default=None),
    db: AsyncSession = Depends(get_session),
):
    await _ensure_vocab_catalog(db, min_per_level=200)
    now = datetime.now(timezone.utc)
    target_diff = _difficulty_by_level(level) if level else None
    items: list[VocabSRSItem] = []
    queued: set[int] = set()

    while _vocab_again_queue and len(items) < limit:
        cid = _vocab_again_queue.pop()
        if cid in queued:
            continue
        row = await db.execute(
            select(VocabCard, VocabSRSState)
            .join(VocabSRSState, VocabSRSState.card_id == VocabCard.id)
            .where(VocabCard.id == cid)
        )
        got = row.first()
        if not got:
            continue
        card, state = got
        if target_diff and card.difficulty != target_diff:
            continue
        items.append(VocabSRSItem(
            card_id=card.id, lemma=card.lemma, meaning_ko=card.meaning_ko,
            example_en=card.example_en, difficulty=card.difficulty, due_at=state.due_at,
            direction=_direction_by_difficulty(card.difficulty),
        ))
        queued.add(cid)

    remaining = limit - len(items)
    if remaining > 0:
        due_query = (
            select(VocabCard, VocabSRSState)
            .join(VocabSRSState, VocabSRSState.card_id == VocabCard.id)
            .where(VocabSRSState.due_at <= now)
        )
        if target_diff:
            due_query = due_query.where(VocabCard.difficulty == target_diff)
        rows = await db.execute(due_query.limit(500))
        due_candidates = rows.all()
        random.shuffle(due_candidates)
        for card, state in due_candidates[:remaining]:
            if card.id in queued:
                continue
            items.append(VocabSRSItem(
                card_id=card.id, lemma=card.lemma, meaning_ko=card.meaning_ko,
                example_en=card.example_en, difficulty=card.difficulty, due_at=state.due_at,
                direction=_direction_by_difficulty(card.difficulty),
            ))
            queued.add(card.id)

    remaining = limit - len(items)
    if remaining > 0:
        fill_query = select(VocabCard, VocabSRSState).join(VocabSRSState, VocabSRSState.card_id == VocabCard.id)
        if target_diff:
            fill_query = fill_query.where(VocabCard.difficulty == target_diff)
        fill_rows = await db.execute(fill_query.limit(500))
        fill_candidates = fill_rows.all()
        random.shuffle(fill_candidates)
        for card, state in fill_candidates:
            if len(items) >= limit:
                break
            if card.id in queued:
                continue
            items.append(VocabSRSItem(
                card_id=card.id, lemma=card.lemma, meaning_ko=card.meaning_ko,
                example_en=card.example_en, difficulty=card.difficulty, due_at=state.due_at,
                direction=_direction_by_difficulty(card.difficulty),
            ))
            queued.add(card.id)
    return items


@router.post("/vocab/srs/review", response_model=VocabReviewOut)
async def vocab_srs_review(payload: VocabReviewIn, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, payload.card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    state, quality = await apply_vocab_review(db, payload.card_id, payload.grade)
    if payload.grade == "again":
        _vocab_again_queue.append(payload.card_id)
    await db.commit()
    return VocabReviewOut(
        card_id=payload.card_id,
        grade=payload.grade,
        quality=quality,
        next_due_at=state.due_at,
        ease=state.ease,
        interval_days=state.interval_days,
        reps=state.reps,
    )


@router.get("/vocab/quiz/mcq/next", response_model=list[VocabMCQItem])
async def vocab_mcq_next(
    limit: int = Query(10, ge=1, le=50),
    level: VocabLevel = Query("beginner"),
    card_ids: Optional[List[int]] = Query(default=None),
    db: AsyncSession = Depends(get_session),
):
    await _ensure_vocab_catalog(db, min_per_level=200)
    picked: list[VocabCard] = []

    if card_ids:
        selected_ids: list[int] = []
        seen_ids: set[int] = set()
        for cid in card_ids:
            if cid in seen_ids:
                continue
            seen_ids.add(cid)
            selected_ids.append(cid)
            if len(selected_ids) >= limit:
                break
        if selected_ids:
            rows = await db.execute(select(VocabCard).where(VocabCard.id.in_(selected_ids)))
            by_id = {card.id: card for card in rows.scalars().all()}
            picked = [by_id[cid] for cid in selected_ids if cid in by_id]
    else:
        diff = _difficulty_by_level(level)
        recent = set(_vocab_mcq_recent[level])
        rows = await db.execute(select(VocabCard).where(VocabCard.difficulty == diff).order_by(VocabCard.id.desc()).limit(300))
        cards = rows.scalars().all()
        pool = [c for c in cards if c.id not in recent]
        if len(pool) < limit:
            pool = list(cards)
        random.shuffle(pool)
        picked = pool[:limit]

    out: list[VocabMCQItem] = []
    for card in picked:
        direction = _direction_by_difficulty(card.difficulty)
        if card.difficulty <= 1:
            direction = "word_to_meaning"
        elif card.difficulty == 2:
            direction = "meaning_to_word"

        distractor_query = (
            select(VocabCard)
            .where(VocabCard.difficulty == card.difficulty)
            .where(VocabCard.id != card.id)
        )
        if card.pos:
            distractor_query = distractor_query.where(VocabCard.pos == card.pos)
        distractors_rows = await db.execute(distractor_query.limit(80))
        distractor_cards = distractors_rows.scalars().all()
        if len(distractor_cards) < 3:
            fallback = await db.execute(select(VocabCard).where(VocabCard.id != card.id).order_by(VocabCard.id.desc()).limit(120))
            distractor_cards = fallback.scalars().all()

        if direction == "word_to_meaning":
            choices, answer_index = _pick_unique_choices(card.meaning_ko, [c.meaning_ko for c in distractor_cards])
            out.append(VocabMCQItem(
                card_id=card.id, level=_level_by_difficulty(card.difficulty), direction=direction,
                question_text=card.lemma, choices=choices[:4], answer_index=answer_index,
            ))
        else:
            choices, answer_index = _pick_unique_choices(card.lemma, [c.lemma for c in distractor_cards])
            out.append(VocabMCQItem(
                card_id=card.id, level=_level_by_difficulty(card.difficulty), direction=direction,
                question_text=card.meaning_ko, choices=choices[:4], answer_index=answer_index,
            ))
        _vocab_mcq_recent[level].append(card.id)
    return out
