# server/app/main.py
from __future__ import annotations

from datetime import datetime, timezone
from fastapi import FastAPI, UploadFile, File, HTTPException
from app.db import init_db
from app.config_loader import load_writing_bundle

app = FastAPI(
    title="english_ai server",
    version="0.1.0",
    description="FastAPI backend for AI English learning app (capstone, no-Git).",
)


# ----- Lifecycle -----
@app.on_event("startup")
async def on_startup():
    # Initialize DB connection/metadata
    await init_db()


# ----- Health -----
@app.get("/healthz")
def health():
    return {"ok": True, "time": datetime.now(timezone.utc).isoformat()}


# ----- Speech Turn (demo) -----
@app.post("/speech/turn")
async def speech_turn(file: UploadFile = File(...)):
    """
    Accepts an audio file and returns minimal metadata + demo transcript.
    Replace with real STT pipeline when ready.
    """
    audio_bytes = await file.read()
    return {
        "filename": file.filename,
        "size_bytes": len(audio_bytes),
        "transcript": "demo transcript",
        "duration_ms": 0,
        "received_at": datetime.now(timezone.utc).isoformat(),
    }


# ----- Writing Prompt Bundle -----
@app.get("/prompts/writing")
def get_writing_prompt():
    """
    Exposes the writing prompt + guardrails bundle defined in config/modes.yaml.
    Requires mode 'writing_v1' with prompt_file/guardrails_file mappings.
    """
    try:
        bundle = load_writing_bundle("writing_v1")
    except KeyError as e:
        # Mode not found or mappings missing
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        # Any unexpected read/parse error
        raise HTTPException(status_code=500, detail=f"failed to load writing prompt: {e}")
    return {
        **bundle,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }