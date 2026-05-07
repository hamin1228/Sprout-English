from __future__ import annotations

import os
from typing import Dict, List, Optional, Tuple

from fastapi import APIRouter, File, HTTPException, Request, UploadFile, status

from app.core.audio import (
    DEFAULT_OPENAI_TIMEOUT_S,
    DEFAULT_WHISPER_MODEL,
    validate_and_save_audio,
    _is_unstable_wav_signal,
)
from app.core.logging import log
from app.core.openai_clients import get_sync_client
from app.rate_limit import speech_turn_rate_limiter
from app.stt_pipeline import STTPipeline

router = APIRouter()

_stt_pipeline: STTPipeline | None = None


def _stt_openai_transcribe_file(path: str, language: str | None = None) -> Tuple[str, List[Dict]]:
    client = get_sync_client()
    model = (os.getenv("OPENAI_WHISPER_MODEL") or DEFAULT_WHISPER_MODEL).strip()
    if not model:
        raise RuntimeError("openai_stt_model_not_configured")
    timeout_s = float(os.getenv("OPENAI_TIMEOUT_S") or DEFAULT_OPENAI_TIMEOUT_S)
    kwargs: Dict = {"model": model}
    lang_norm = (language or "").strip().lower()
    if language and lang_norm not in ("", "auto"):
        kwargs["language"] = language
    try:
        with open(path, "rb") as f:
            resp = client.audio.transcriptions.create(
                file=f, response_format="verbose_json", timeout=timeout_s, **kwargs
            )
        transcript = getattr(resp, "text", "") or ""
        segments = []
        if hasattr(resp, "segments") and resp.segments:
            for seg in resp.segments:
                try:
                    segments.append({
                        "start_ms": int(seg.start * 1000),
                        "end_ms": int(seg.end * 1000),
                        "text": seg.text.strip(),
                    })
                except Exception:
                    continue
        return (transcript, segments)
    except Exception as e:
        log.error(f"Whisper API failed: {type(e).__name__}: {str(e)}", trace_id="-")
        raise


def _stub_stt(_: bytes, __: str) -> Tuple[str, List[Dict]]:
    return ("demo transcript", [
        {"start_ms": 0, "end_ms": 1000, "text": "demo"},
        {"start_ms": 1000, "end_ms": 2000, "text": "transcript"},
    ])


@router.post("/speech/turn")
async def speech_turn(
    request: Request,
    file: UploadFile = File(...),
    language: Optional[str] = None,
):
    client_ip = request.client.host if request.client else "unknown"
    if not speech_turn_rate_limiter.allow(client_ip):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many /speech/turn requests, please slow down.",
        )

    info = await validate_and_save_audio(file, request)
    audio_path = info["audio_path"]
    duration_ms = int(info["duration_ms"] or 0)
    signal_profile = info.get("signal_profile")

    if _is_unstable_wav_signal(signal_profile):
        log.warning(
            "Unstable mic input detected profile=%s path=%s",
            signal_profile,
            audio_path,
            trace_id=getattr(request.state, "trace_id", "-"),
        )
        return {
            "trace_id": getattr(request.state, "trace_id", None),
            "filename": info["original_filename"],
            "size_bytes": info["bytes"],
            "duration_ms": duration_ms,
            "transcript": "",
            "segments": [],
            "audio_url": info["audio_url"],
            "provider": "signal_guard",
            "error": "mic_input_unstable",
            "signal_profile": signal_profile,
        }

    trace_id = getattr(request.state, "trace_id", "-")
    log.info(
        f"STT Request: {audio_path}, Size: {info['bytes']} bytes, Duration: {duration_ms} ms",
        trace_id=trace_id,
    )

    provider = "pipeline"
    transcript = ""
    segments: List[Dict] = []

    if _stt_pipeline is not None:
        try:
            with open(audio_path, "rb") as f:
                audio_bytes = f.read()
            result = _stt_pipeline.run(audio_bytes)
            if result.get("sentences"):
                transcript = " ".join(s["text"] for s in result["sentences"] if s["text"])
            segments = result.get("segments", [])
        except Exception as e:
            log.warning(f"STTPipeline failed: {e}, falling back to Whisper", trace_id=trace_id)
            provider = "openai"
            try:
                transcript, segments = _stt_openai_transcribe_file(audio_path, language)
            except Exception as e2:
                log.warning("STT failed; using stub: %r", e2, trace_id=trace_id)
                transcript, segments = _stub_stt(b"", language or "")
                provider = "stub"
    else:
        provider = "openai"
        log.info(f"Calling Whisper API for {audio_path}", trace_id=trace_id)
        try:
            transcript, segments = _stt_openai_transcribe_file(audio_path, language)
            invalid_transcripts = ["BELL", "[BLANK_AUDIO]", "(bell ringing)", "(silence)", "[Music]", "[음악]"]
            transcript_clean = transcript.strip()
            if transcript_clean.upper() in [x.upper() for x in invalid_transcripts] or len(transcript_clean) < 2:
                log.warning(f'Invalid transcript filtered: "{transcript}"', trace_id=trace_id)
                transcript = ""
                segments = []
        except Exception as e:
            log.error(f"Whisper API failed: {type(e).__name__}: {str(e)}", trace_id=trace_id)
            transcript, segments = _stub_stt(b"", language or "")
            provider = "stub"

    return {
        "trace_id": getattr(request.state, "trace_id", None),
        "filename": info["original_filename"],
        "size_bytes": info["bytes"],
        "duration_ms": duration_ms,
        "transcript": transcript,
        "segments": segments,
        "audio_url": info["audio_url"],
        "provider": provider,
    }
