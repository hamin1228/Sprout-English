from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import PlainTextResponse, JSONResponse
from pathlib import Path
from app.db import init_db

app = FastAPI()
APP_DIR = Path(__file__).resolve().parent
PROMPT_DIR = (APP_DIR.parent / "config" / "prompts")

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

def _read_textfile(name: str) -> str:
    p = PROMPT_DIR / name
    if not p.exists():
        raise HTTPException(status_code=404, detail=f"{name} not found")
    return p.read_text(encoding="utf-8")

@app.get("/prompts/freetalk", response_class=PlainTextResponse)
def get_freetalk_prompt():
    return _read_textfile("prompt_freetalk_v1.md")

@app.get("/prompts/safety", response_class=PlainTextResponse)
def get_safety_templates():
    return _read_textfile("safety_responses.md")

@app.get("/prompts/examples")
def get_examples_overview():
    name = "examples.jsonl"
    text = _read_textfile(name)
    lines = [ln for ln in text.splitlines() if ln.strip()]
    # minimal JSONL validation (best-effort)
    valid = 0
    import json
    for ln in lines:
        try:
            json.loads(ln)
            valid += 1
        except Exception:
            pass
    return JSONResponse({"file": name, "lines": len(lines), "valid_jsonl_lines": valid})
