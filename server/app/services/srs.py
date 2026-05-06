# [NEW-ONLY COMMENT]
# SRS(Spaced Repetition) 헬퍼 모듈 — 이번 주 추가된 코드 설명 전용 주석
# 목적
# - Mistake에 대한 복습 간격/난이도(ease) 계산과 상태 초기화/갱신 로직을 분리
# 특징
# - SM-2 유사 규칙 사용(quality 0~5)
# - async 세션에서 lazy-load를 피하여 MissingGreenlet 오류 회피
#   (relationship 직접 접근 대신 명시적 SELECT 사용)
# 사용처
# - /mistakes 생성 시 ensure_initial_state()
# - /srs/review 호출 시 apply_review()
from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models import Mistake, SRSState, Review

# [NEW] ease 조정 함수
# - SM-2에서 사용하는 경험식: ease' = ease - 0.8 + 0.28*q - 0.02*q^2
# - 경계: 1.3 <= ease <= 3.5 로 클램프
# - q: 품질(0~5)
def _adj_ease(ease: float, q: int) -> float:
    # SM-2 ease update (bounded)
    new_ease = ease - 0.8 + 0.28*q - 0.02*(q*q)
    return max(1.3, min(3.5, new_ease))

# [NEW] 초기 SRS 상태 보장
# - 목적: Mistake 생성 직후에도 SRSState가 존재하도록 보장(due_at=now)
# - 구현: relationship lazy-load( mistake.srs_state )를 건드리지 않고
#        명시적 SELECT 로 상태 조회 → 없으면 기본값으로 생성/flush
# - 주의: MissingGreenlet 회피를 위해 항상 명시적 쿼리 패턴 유지
async def ensure_initial_state(db: AsyncSession, mistake: Mistake) -> SRSState:
    # Avoid async lazy-load (which triggers MissingGreenlet) by not touching mistake.srs_state
    state = await db.scalar(select(SRSState).where(SRSState.mistake_id == mistake.id))
    if state:
        return state

    now = datetime.now(timezone.utc)
    state = SRSState(
        mistake_id=mistake.id,
        ease=2.5,
        interval_days=1.0,
        reps=0,
        due_at=now,
    )
    db.add(state)
    await db.flush()
    return state

# [NEW] 리뷰 반영 및 다음 due 계산
# - 입력: mistake_id, quality(0~5)
# - 효과:
#   · Review 레코드 추가(reviewed_at=now)
#   · quality<3: 실패 → reps=0, interval=1, ease 하향
#   · quality>=3: 성공 → reps+=1, ease 조정,
#       reps==1 → interval=1, reps==2 → interval=6,
#       그 이후 → interval *= ease (SM-2 유사)
#   · last_reviewed_at=now, due_at=now+interval_days
# - 반환: 갱신된 SRSState (commit은 호출측에서 수행)
async def apply_review(db: AsyncSession, mistake_id: int, quality: int) -> SRSState:
    now = datetime.now(timezone.utc)
    state = await db.scalar(select(SRSState).where(SRSState.mistake_id == mistake_id))
    if not state:
        state = SRSState(mistake_id=mistake_id, ease=2.5, interval_days=1.0, reps=0, due_at=now)
        db.add(state)
        await db.flush()

    # record review
    db.add(Review(mistake_id=mistake_id, quality=quality, reviewed_at=now))

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
    return state