from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import VocabReviewLog, VocabSRSState

GRADE_TO_QUALITY: dict[str, int] = {
    "again": 1,
    "hard": 3,
    "good": 4,
    "easy": 5,
}


def _adj_ease(ease: float, q: int) -> float:
    new_ease = ease - 0.8 + 0.28 * q - 0.02 * (q * q)
    return max(1.3, min(3.5, new_ease))


async def ensure_vocab_state(db: AsyncSession, card_id: int) -> VocabSRSState:
    state = await db.scalar(select(VocabSRSState).where(VocabSRSState.card_id == card_id))
    if state:
        return state
    now = datetime.now(timezone.utc)
    state = VocabSRSState(
        card_id=card_id,
        ease=2.5,
        interval_days=1.0,
        reps=0,
        due_at=now,
    )
    db.add(state)
    await db.flush()
    return state


async def apply_vocab_review(db: AsyncSession, card_id: int, grade: str) -> tuple[VocabSRSState, int]:
    quality = GRADE_TO_QUALITY[grade]
    state = await ensure_vocab_state(db, card_id)
    now = datetime.now(timezone.utc)
    db.add(VocabReviewLog(card_id=card_id, grade=grade, quality=quality, reviewed_at=now))

    if quality < 3:
        state.reps = 0
        state.interval_days = 1.0
        state.ease = _adj_ease(state.ease, quality)
    else:
        state.reps += 1
        state.ease = _adj_ease(state.ease, quality)
        if state.reps == 1:
            state.interval_days = 1.0
        elif state.reps == 2:
            state.interval_days = 6.0
        else:
            state.interval_days = round(state.interval_days * state.ease, 2)

    state.last_reviewed_at = now
    state.due_at = now + timedelta(days=state.interval_days)
    return state, quality
