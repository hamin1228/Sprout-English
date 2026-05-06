from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import PlainTextResponse
from pathlib import Path
from typing import List
from app.db import init_db
from app.schemas import TOEICEvalRequest, TOEICEvalResponseItem, TOEICEvalResponse, TOEICItem

app = FastAPI()

BASE_DIR = Path(__file__).resolve().parents[1]  # server/
TEMPLATES_MD = BASE_DIR / "docs" / "templates_toeic.md"

@app.on_event("startup")
async def on_startup():
    await init_db()

@app.get("/healthz")
def health():
    return {"ok": True}

@app.post("/speech/turn")
async def speech_turn(file: UploadFile = File(...)):
    audio_bytes = await file.read()
    return {
        "filename": file.filename,
        "size_bytes": len(audio_bytes),
        "transcript": "demo transcript",
        "duration_ms": 0,
    }

@app.get("/toeic/templates", response_class=PlainTextResponse)
async def get_toeic_templates():
    if not TEMPLATES_MD.exists():
        raise HTTPException(status_code=404, detail="templates_toeic.md not found")
    try:
        return TEMPLATES_MD.read_text(encoding="utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def _eval_item(item: TOEICItem) -> TOEICEvalResponseItem:
    reasons: List[str] = []
    checks = 0
    passed_checks = 0

    # 1) 옵션 4개
    checks += 1
    if len(item.options) == 4:
        passed_checks += 1
    else:
        reasons.append("options must be exactly 4")

    # 2) 중복 옵션 없음
    checks += 1
    if len(set([opt.strip() for opt in item.options])) == 4:
        passed_checks += 1
    else:
        reasons.append("duplicate options")

    # 3) answer_index 유효 & 정답 존재
    checks += 1
    if 0 <= item.answer_index < 4 and item.options[item.answer_index].strip():
        passed_checks += 1
    else:
        reasons.append("invalid answer_index")

    # 4) 파트 검증
    checks += 1
    if item.part in (5, 6, 7):
        passed_checks += 1
    else:
        reasons.append("part must be 5/6/7")

    # 5) 길이 휴리스틱(너무 짧거나 긴 문항 방지)
    stem_len = len(item.stem.split())
    checks += 1
    if item.part == 5 and 6 <= stem_len <= 30:
        passed_checks += 1
    elif item.part in (6, 7) and 20 <= stem_len <= 400:
        passed_checks += 1
    else:
        reasons.append("stem length out of expected range")

    score = passed_checks / max(checks, 1)
    return TOEICEvalResponseItem(index=0, passed=(score >= 0.8), score=round(score, 3), reasons=reasons)

@app.post("/toeic/eval")
async def eval_toeic(req: TOEICEvalRequest):
    results: List[TOEICEvalResponseItem] = []
    for idx, it in enumerate(req.items):
        r = _eval_item(it)
        r.index = idx
        results.append(r)
    return TOEICEvalResponse(ok=True, count=len(results), results=results)
