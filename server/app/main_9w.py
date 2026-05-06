from fastapi import FastAPI, UploadFile, File, HTTPException
from app.db import init_db
from app.config_loader import load_goal_rules, load_patterns, load_tone_guides
from app.schemas import EvalGoalRequest, EvalGoalResult, PhraseHit
from app.eval import evaluate_transcript

app = FastAPI(title="english_ai")

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

@app.get("/config/goals")
def get_goals():
    return load_goal_rules()

@app.get("/config/patterns")
def get_patterns():
    return {"rows": load_patterns()}

@app.get("/config/tone-guides")
def get_tone_guides():
    return {"markdown": load_tone_guides()}

@app.post("/eval/goal", response_model=EvalGoalResult)
def eval_goal(req: EvalGoalRequest):
    try:
        result = evaluate_transcript(req.transcript, req.goalset_id, req.tone_override)
        # Pydantic casting to conform to response_model
        return EvalGoalResult(
            goalset_id=result["goalset_id"],
            coverage_ratio=result["coverage_ratio"],
            score=result["score"],
            passed=result["passed"],
            required_hits=[PhraseHit(**h) for h in result["required_hits"]],
            missing_phrases=result["missing_phrases"],
            tone_score=result["tone_score"],
            tone_warnings=result["tone_warnings"],
            suggestions=result["suggestions"],
            details=result["details"],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))