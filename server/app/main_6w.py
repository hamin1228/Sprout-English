from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import ValidationError
from typing import Optional, Dict, Any, List, Tuple
from pathlib import Path
import json

# =========================
# 경로: server/config/...
# =========================
SERVER_DIR = Path(__file__).resolve().parents[1]   # .../server
CONFIG_DIR = SERVER_DIR / "config"                 # .../server/config
RUBRICS_DIR = CONFIG_DIR / "rubrics"               # .../server/config/rubrics
PROMPTS_DIR = CONFIG_DIR / "prompts"               # .../server/config/prompts
RUBRIC_PATH = RUBRICS_DIR / "rubric_weights.json"
TEMPLATE_PATH = PROMPTS_DIR / "feedback_template.md"

def ensure_dirs():
    RUBRICS_DIR.mkdir(parents=True, exist_ok=True)
    PROMPTS_DIR.mkdir(parents=True, exist_ok=True)

# =========================
# 스키마 (외부 파일 사용)
# =========================
from .schemas import (
    RubricWeights,
    RubricUpdate,
    FeedbackGenerateRequest,
    FeedbackResponse,
)

# =========================
# 파일 I/O 유틸
# =========================
def load_weights() -> RubricWeights:
    ensure_dirs()
    if not RUBRIC_PATH.exists():
        w = RubricWeights()
        save_weights(w)
        return w
    with open(RUBRIC_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return RubricWeights(
        pronunciation=float(data.get("pronunciation", 0.40)),
        fluency=float(data.get("fluency", 0.35)),
        logic=float(data.get("logic", 0.25)),
    )

def save_weights(weights: RubricWeights) -> None:
    ensure_dirs()
    with open(RUBRIC_PATH, "w", encoding="utf-8") as f:
        json.dump(
            {
                "pronunciation": float(weights.pronunciation),
                "fluency": float(weights.fluency),
                "logic": float(weights.logic),
                "_notes": "합이 1이 아니어도 서버가 정규화합니다. 음수는 불가.",
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

def load_template() -> str:
    ensure_dirs()
    if not TEMPLATE_PATH.exists():
        default = (
            "# Mini Feedback (v1)\n\n"
            "**Overall**: {overall}/100\n"
            "**Weights** → Pron: {pron_w}, Flu: {flu_w}, Logic: {logic_w}\n\n"
            "## Minimal-change suggestions (no over-correction)\n"
            "- Apply only necessary fixes. Keep your voice.\n\n"
            "### Example\n- Before: {example_before}\n- After: {example_after}\n\n"
            "## Tips\n{tips}\n"
        )
        TEMPLATE_PATH.write_text(default, encoding="utf-8")
        return default
    return TEMPLATE_PATH.read_text(encoding="utf-8")

# =========================
# 경량 분석 / 템플릿 렌더
# =========================
def _light_analysis(transcript: str) -> Tuple[str, str, List[str]]:
    text = transcript.strip()
    if not text:
        return "—", "—", ["Say one full sentence next time."]
    lower = text.lower()
    fillers = {"um", "uh", "like", "you know", "kind of"}
    filler_hits = sum(lower.count(w) for w in fillers)

    example_before = "I am go to the library."
    example_after = "I'm going to the library."
    tips = []
    if filler_hits > 0:
        tips.append("Replace fillers with a short pause (2 beats).")
    tips.append("Keep sentences short (≤ 12 words) for clarity.")
    tips.append("Stress content words; de-stress function words.")
    return example_before, example_after, tips[:3]

def render_feedback_template(template: str, w_norm: RubricWeights, overall: float | None, transcript: str) -> str:
    ex_before, ex_after, tips = _light_analysis(transcript)
    mapping: Dict[str, Any] = {
        "overall": f"{overall:.1f}" if overall is not None else "—",
        "pron_w": f"{float(w_norm.pronunciation):.2f}",
        "flu_w": f"{float(w_norm.fluency):.2f}",
        "logic_w": f"{float(w_norm.logic):.2f}",
        "example_before": ex_before,
        "example_after": ex_after,
        "tips": "- " + "\n- ".join(tips) if tips else "—",
    }
    try:
        return template.format(**mapping)
    except Exception:
        return (
            f"Overall: {mapping['overall']}\n"
            f"Weights -> Pron {mapping['pron_w']}, Flu {mapping['flu_w']}, Logic {mapping['logic_w']}\n"
            f"Before: {mapping['example_before']}\nAfter: {mapping['example_after']}\n"
            f"Tips:\n{mapping['tips']}\n"
        )

def weighted_overall(scores: Dict[str, float], w_norm: RubricWeights) -> float:
    p = float(scores.get("pronunciation", 0))
    f = float(scores.get("fluency", 0))
    l = float(scores.get("logic", 0))
    return p * float(w_norm.pronunciation) + f * float(w_norm.fluency) + l * float(w_norm.logic)

# =========================
# FastAPI 앱
# =========================
from app.db import init_db  # 기존 DB 초기화 유지

app = FastAPI()

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

# ---- 루브릭 가중치 ----
@app.get("/config/rubric")
def get_rubric():
    w = load_weights()
    wn = w.normalized()
    return {"raw": w.model_dump(), "normalized": wn.model_dump()}

@app.put("/config/rubric")
def put_rubric(update: RubricUpdate):
    try:
        cur = load_weights()
        data = cur.model_dump()
        if update.pronunciation is not None:
            data["pronunciation"] = float(update.pronunciation)
        if update.fluency is not None:
            data["fluency"] = float(update.fluency)
        if update.logic is not None:
            data["logic"] = float(update.logic)
        new_w = RubricWeights(**data)
        save_weights(new_w)
        return {"saved_raw": new_w.model_dump(), "normalized": new_w.normalized().model_dump()}
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))

# ---- 피드백 템플릿 ----
@app.get("/feedback/template", response_class=PlainTextResponse)
def get_feedback_template():
    return load_template()

# ---- 피드백 생성 ----
@app.post("/feedback/generate", response_model=FeedbackResponse)
def post_feedback(req: FeedbackGenerateRequest):
    w = load_weights().normalized()
    overall: Optional[float] = None
    if req.scores:
        overall = weighted_overall(req.scores, w)
    tpl = load_template()
    mini = render_feedback_template(tpl, w, overall, req.transcript)
    return FeedbackResponse(
        overall=round(overall, 1) if overall is not None else None,
        weights=w,
        mini_feedback=mini,
        used_template="config/prompts/feedback_template.md",
    )