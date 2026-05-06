# server/app/main.py
from fastapi import FastAPI, UploadFile, File, HTTPException
from app.db import init_db
from app.schemas import SpeechTurnResponse, Segment, Sentence
from app.stt_pipeline import STTPipeline
import os

CFG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "stt.yaml")
DICT_PATH = os.path.join(os.path.dirname(__file__), "..", "dictionaries", "custom_words.json")

app = FastAPI()
pipeline: STTPipeline | None = None

@app.on_event("startup")
async def on_startup():
    global pipeline
    await init_db()
    pipeline = STTPipeline(cfg_path=os.path.abspath(CFG_PATH), dict_path=os.path.abspath(DICT_PATH))

@app.get("/healthz")
def health():
    return {"ok": True}

@app.post("/config/reload")
def reload_config():
    if pipeline is None:
        raise HTTPException(500, "Pipeline not initialized")
    pipeline.reload()
    return {"reloaded": True}

@app.post("/speech/turn", response_model=SpeechTurnResponse)
async def speech_turn(file: UploadFile = File(...)):
    if pipeline is None:
        raise HTTPException(500, "Pipeline not initialized")
    audio_bytes = await file.read()
    result = pipeline.run(audio_bytes)
    return SpeechTurnResponse(
        filename=file.filename,
        size_bytes=len(audio_bytes),
        sample_rate=result["sample_rate"],
        segments=[Segment(**s) for s in result["segments"]],
        sentences=[Sentence(**s) for s in result["sentences"]],
        notes="STT engine not connected yet (dummy). Only VAD/segmentation/sentence rules applied."
    )