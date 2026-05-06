from __future__ import annotations

import asyncio
import logging
import os
import tempfile
import uuid
import wave
from pathlib import Path
from typing import Optional

from fastapi import HTTPException, Request
from pydantic import BaseModel
from starlette.responses import JSONResponse

from app import realtime_speech as realtime_speech_module
from app.local_stt_switch import LocalSttManager
from app.main import app


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() not in {"0", "false", "no", "off"}


manager = LocalSttManager()
log = logging.getLogger("app.main_local_stt")


def _local_realtime_transcribe_file(audio_path: str, language: Optional[str] = None):
    result = manager.transcribe(audio_path=audio_path, provider=None, language=language)
    return result.transcript, result.segments


# /speech/realtime fallback transcription also uses local STT manager.
realtime_speech_module.transcribe_file = _local_realtime_transcribe_file
realtime_speech_module.REALTIME_TRANSCRIBE_MODE = "buffered"
# Hard-disable OpenAI realtime transcription path in local STT mode.
realtime_speech_module._should_try_realtime_models = lambda: False
realtime_speech_module.NO_SPEECH_GRACE_MS = int(
    os.getenv("LOCAL_STT_REALTIME_NO_SPEECH_GRACE_MS", "0")
)
realtime_speech_module.FINAL_TRANSCRIPT_TIMEOUT_MS = int(
    os.getenv("LOCAL_STT_REALTIME_FINAL_TRANSCRIPT_TIMEOUT_MS", "0")
)


class ActiveProviderRequest(BaseModel):
    provider: str
    language: Optional[str] = None


@app.on_event("startup")
async def preload_local_stt_models() -> None:
    result = await asyncio.to_thread(manager.preload_startup)
    log.info("local_stt_preload result=%s", result)


@app.get("/speech/providers")
async def local_stt_provider_status() -> JSONResponse:
    return JSONResponse(manager.list_status())


@app.get("/speech/provider/active")
async def local_stt_active_provider() -> JSONResponse:
    return JSONResponse(
        {
            "active_provider": manager.active_provider,
            "active_language": manager.active_language,
        }
    )


@app.post("/speech/provider/active")
async def local_stt_set_active_provider(body: ActiveProviderRequest) -> JSONResponse:
    try:
        payload = manager.set_active_provider(body.provider, body.language)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return JSONResponse(payload)


@app.middleware("http")
async def override_speech_turn_with_local_stt(request: Request, call_next):
    # Keep original app behavior for all routes except POST /speech/turn.
    if request.url.path != "/speech/turn" or request.method.upper() != "POST":
        return await call_next(request)

    trace_id = str(uuid.uuid4())

    try:
        form = await request.form()
    except Exception as exc:
        return JSONResponse(
            status_code=400,
            content={
                "trace_id": trace_id,
                "error": f"bad_multipart:{type(exc).__name__}",
            },
        )

    upload = form.get("file")
    if upload is None or not hasattr(upload, "read"):
        return JSONResponse(
            status_code=400,
            content={"trace_id": trace_id, "error": "missing_file"},
        )

    filename = getattr(upload, "filename", None) or "speech.wav"
    suffix = Path(filename).suffix.lower() or ".wav"

    try:
        raw = await upload.read()
    except Exception as exc:
        return JSONResponse(
            status_code=400,
            content={
                "trace_id": trace_id,
                "filename": filename,
                "error": f"file_read_failed:{type(exc).__name__}",
            },
        )

    if not raw:
        return JSONResponse(
            status_code=400,
            content={
                "trace_id": trace_id,
                "filename": filename,
                "error": "empty_audio",
            },
        )

    query_provider = request.query_params.get("provider")
    query_language = request.query_params.get("language")

    fd, tmp_path = tempfile.mkstemp(prefix="local_stt_", suffix=suffix)
    os.close(fd)

    try:
        with open(tmp_path, "wb") as f:
            f.write(raw)

        result = manager.transcribe(
            audio_path=tmp_path,
            provider=query_provider,
            language=query_language,
        )

        transcript = (result.transcript or "").strip()
        words = transcript.split()
        duration_ms = _duration_ms(tmp_path, suffix)
        wpm = round((len(words) * 60000 / duration_ms), 1) if duration_ms > 0 else 0.0

        payload = {
            "trace_id": trace_id,
            "filename": filename,
            "size_bytes": len(raw),
            "duration_ms": duration_ms,
            "transcript": transcript,
            "segments": result.segments,
            "audio_url": None,
            "provider": result.provider,
            "model": result.model,
            "active_provider": manager.active_provider,
            "active_language": manager.active_language,
            "scores": {
                "pronunciation": 0,
                "fluency": 0,
                "logic": 0,
            },
            "metrics": {
                "duration_ms": duration_ms,
                "word_count": len(words),
                "wpm": wpm,
            },
        }
        return JSONResponse(payload)

    except ValueError as exc:
        return JSONResponse(
            status_code=400,
            content={
                "trace_id": trace_id,
                "filename": filename,
                "error": str(exc),
            },
        )
    except Exception as exc:
        return JSONResponse(
            status_code=503,
            content={
                "trace_id": trace_id,
                "filename": filename,
                "error": f"local_stt_failed:{type(exc).__name__}:{exc}",
                "provider": (query_provider or manager.active_provider),
            },
        )
    finally:
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass


def _duration_ms(audio_path: str, suffix: str) -> int:
    if suffix not in {".wav", ".wave"}:
        return 0

    try:
        with wave.open(audio_path, "rb") as wav:
            frames = wav.getnframes()
            rate = wav.getframerate()
            if rate <= 0:
                return 0
            return int((frames * 1000) / rate)
    except Exception:
        return 0
