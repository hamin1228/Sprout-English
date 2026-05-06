# server/app/main.py
from __future__ import annotations

"""
FastAPI 메인 엔트리포인트 (캡스톤 MVP)
- 기본 헬스체크 및 음성 턴 업로드 엔드포인트
- 태그 정규화, 오늘의 표현 생성
- 목표/표현 달성 평가 (eval/goal)
"""

from pathlib import Path
from typing import Optional

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse

# DB 초기화
from app.db import init_db

# 스키마
from app.schemas import (
    NormalizeTagsRequest,
    NormalizeTagsResponse,
    ExpressionRequest,
    ExpressionResponse,
    ExpressionItem,
    EvalGoalRequest,
    EvalGoalResult,
)

# 서비스 로직
from app.services.tags import TagNormalizer
from app.services.expression import generate_expressions

# 평가 로직(evaluate_transcript)
from app.eval import evaluate_transcript


# =========================================================
# 앱 초기화
# =========================================================
app = FastAPI(
    title="english-ai-server",
    version="0.1.0",
    description="AI English MVP (FastAPI)",
)

# 오디오 저장 디렉터리 (server/app/storage/audio)
AUDIO_DIR = Path(__file__).resolve().parent / "storage" / "audio"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

# 태그 정규화기 (경로 자동 탐색: config/dictionaries → dictionaries → ENV)
try:
    tag_norm = TagNormalizer()
except Exception as e:
    # 초기화 실패 시에도 서버는 기동하되, /tags/normalize 호출 시 에러 발생
    tag_norm = None
    print(f"[WARN] TagNormalizer 초기화 실패: {e}")


# =========================================================
# 라이프사이클
# =========================================================
@app.on_event("startup")
async def on_startup() -> None:
    """애플리케이션 시작 시 DB 초기화"""
    await init_db()


# =========================================================
# 헬스체크
# =========================================================
@app.get("/healthz")
def health() -> dict:
    """간단한 헬스체크"""
    return {"ok": True}


# =========================================================
# 음성 턴 업로드 (스텁)
#   - Android 앱에서 녹음 파일 업로드(form-data: file)
#   - 실제 STT/처리는 이후 파이프라인 연결 예정
# =========================================================
@app.post("/speech/turn")
async def speech_turn(file: UploadFile = File(...)) -> JSONResponse:
    """
    업로드된 오디오를 저장하고 간단한 메타 정보를 반환한다.
    (MVP 단계: transcript/duration은 데모 값)
    """
    audio_bytes = await file.read()

    # 파일 저장 (원본 파일명 유지)
    save_path = AUDIO_DIR / file.filename
    try:
        save_path.write_bytes(audio_bytes)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"오디오 저장 실패: {e}")

    # 기존 베이스라인 스펙에 맞춘 단순 응답
    return JSONResponse(
        {
            "filename": file.filename,
            "size_bytes": len(audio_bytes),
            "transcript": "demo transcript",
            "duration_ms": 0,
        }
    )


# =========================================================
# 태그 정규화
# =========================================================
@app.post("/tags/normalize", response_model=NormalizeTagsResponse)
async def normalize_tags(body: NormalizeTagsRequest) -> NormalizeTagsResponse:
    """
    입력 태그 리스트를 프로젝트 표준 태그로 정규화한다.
    """
    if tag_norm is None:
        raise HTTPException(status_code=500, detail="TagNormalizer가 초기화되지 않았습니다.")
    normalized = tag_norm.normalize(body.raw_tags)
    return NormalizeTagsResponse(normalized=normalized)


# =========================================================
# 오늘의 표현 생성 (레벨/이력 기반)
# =========================================================
@app.post("/expression/today", response_model=ExpressionResponse)
async def expression_today(body: ExpressionRequest) -> ExpressionResponse:
    """
    CEFR 레벨과 최근 학습 이력을 바탕으로 오늘의 표현 후보를 생성한다.
    - 중복/최근 노출 표현을 피하려면 exclude_recent로 전달
    - 다양성은 0.0~1.0 (높을수록 다양)
    """
    hist = tag_norm.normalize(body.history_tags) if tag_norm else body.history_tags
    items = generate_expressions(
        user_level=body.user_level,
        history_tags=hist,
        exclude_recent=set(body.exclude_recent),
        n=body.n,
        diversity=body.diversity,
    )
    return ExpressionResponse(items=[ExpressionItem(**it) for it in items])


# =========================================================
# 목표/표현 달성 평가 (eval/goal)
#   - config/goal_rules.json 기반
# =========================================================
@app.post("/eval/goal", response_model=EvalGoalResult)
async def eval_goal(body: EvalGoalRequest) -> EvalGoalResult:
    """
    transcript가 주어진 goalset의 필수 표현을 얼마나 충족했는지 평가한다.
    tone_override로 goalset의 tone_profile을 임시 변경 가능.
    """
    try:
        res = evaluate_transcript(
            transcript=body.transcript,
            goalset_id=body.goalset_id,
            tone_override=body.tone_override,
        )
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"평가 실패: {e}")
    return EvalGoalResult(**res)


# =========================================================
# 루트(옵션): 간단 안내
# =========================================================
@app.get("/")
def root() -> dict:
    return {
        "service": "english-ai-server",
        "endpoints": [
            "GET  /healthz",
            "POST /speech/turn  (form-data: file)",
            "POST /tags/normalize",
            "POST /expression/today",
            "POST /eval/goal",
        ],
    }