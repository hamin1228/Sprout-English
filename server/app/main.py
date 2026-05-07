from __future__ import annotations

import asyncio
import os
import time
import uuid
from datetime import datetime

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config_loader import settings, get_cors_origins, get_cors_allow_credentials
from app.core.audio import DEFAULT_STORAGE_LOCAL_PATH, DEFAULT_TTS_MODEL, DEFAULT_TTS_VOICE, DEFAULT_TTS_SPEED
from app.db import init_db
from app.metrics import metrics_store
from app.routers import writing
from app.routers.health import router as health_router
from app.routers.speech import router as speech_router
from app.routers.chat import router as chat_router
from app.routers.toeic import router as toeic_router
from app.routers.speaking import router as speaking_router
from app.routers.roleplay import router as roleplay_router
from app.routers.pattern import router as pattern_router
from app.routers.vocab import router as vocab_router
from app.routers.srs import router as srs_router
from app.realtime_speech import register_realtime_speech_routes
from app.tts import router as tts_router

app = FastAPI(
    title=getattr(settings, "APP_NAME", "english_ai"),
    version=getattr(settings, "VERSION", "0.1.0"),
)

# ── CORS ─────────────────────────────────────────────────────────────────────
_cors = get_cors_origins()
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors,
    allow_credentials=get_cors_allow_credentials(),
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(tts_router)
app.include_router(writing.router)
app.include_router(health_router)
app.include_router(speech_router)
app.include_router(chat_router)
app.include_router(toeic_router)
app.include_router(speaking_router)
app.include_router(roleplay_router)
app.include_router(pattern_router)
app.include_router(vocab_router)
app.include_router(srs_router)
register_realtime_speech_routes(app)

# ── Static files ─────────────────────────────────────────────────────────────
_static_dir = getattr(settings, "STORAGE_LOCAL_PATH", DEFAULT_STORAGE_LOCAL_PATH)
app.mount("/static", StaticFiles(directory=_static_dir, html=False), name="static")

# ── Middleware ────────────────────────────────────────────────────────────────

@app.middleware("http")
async def _trace_middleware(request: Request, call_next):
    trace_id = str(uuid.uuid4())
    request.state.trace_id = trace_id
    response: Response = await call_next(request)
    response.headers["X-Trace-Id"] = trace_id
    return response


@app.middleware("http")
async def _metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    status_code = 500
    path = request.url.path
    method = request.method
    key = f"{method} {path}"
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        duration_ms = (time.perf_counter() - start) * 1000.0
        if not path.startswith("/metrics"):
            await metrics_store.record_request(key=key, status_code=status_code, duration_ms=duration_ms)


# ── Startup ───────────────────────────────────────────────────────────────────

async def _init_db_background() -> None:
    import logging
    log = logging.getLogger("app.main")
    try:
        await asyncio.wait_for(init_db(), timeout=5.0)
        log.info("Database schema initialized successfully.")
    except Exception as e:
        log.warning("Database schema initialization failed: %r", e)


@app.on_event("startup")
async def startup_event():
    app.state.started_at = datetime.utcnow()
    os.environ.setdefault("OPENAI_TTS_MODEL", DEFAULT_TTS_MODEL)
    os.environ.setdefault("OPENAI_TTS_VOICE", DEFAULT_TTS_VOICE)
    os.environ.setdefault("OPENAI_TTS_SPEED", DEFAULT_TTS_SPEED)
    asyncio.create_task(_init_db_background())
