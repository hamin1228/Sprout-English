from __future__ import annotations

"""
AI English App — TTS Router (FastAPI)
-------------------------------------
역할(Role)
- OpenAI TTS를 사용해 문장 단위로 오디오(PCM)를 합성해 NDJSON으로 스트리밍합니다.
- 키가 없거나 오류 시에는 톤(비프음)으로 안전 폴백 합니다.
- 디바이스 모드(?device=true)일 때는 PCM을 보내지 않고 문장 텍스트만 내려 트래픽/비용을 절감합니다.
"""

import asyncio
import base64
import io
import json
import os
import re
import tempfile
import wave
from pathlib import Path
from typing import AsyncGenerator, List, Optional

from fastapi import APIRouter, Body, HTTPException, Query
from fastapi.responses import Response, StreamingResponse

# --- Optional: OpenAI SDK (없으면 톤으로 폴백) -------------------------------
try:
    from openai import OpenAI  # type: ignore
except Exception:  # pragma: no cover
    OpenAI = None  # type: ignore

TTS_BUILD = "2026-04-20_openai_restore_v1"
print(f"[TTS] build {TTS_BUILD} loaded from {__file__}")

router = APIRouter()


def _resolve_tts_speed(value: Optional[float]) -> float:
    raw = value
    if raw is None:
        env_raw = os.getenv("OPENAI_TTS_SPEED", "1.0").strip()
        try:
            raw = float(env_raw)
        except Exception:
            raw = 1.0
    return max(0.25, min(4.0, float(raw)))


# ----------------------------- sentence utils ---------------------------------
def _split_sentences(text: str) -> List[str]:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p for p in parts if p]


def _prepare_text_for_tts(text: str) -> str:
    cleaned = text
    cleaned = re.sub(r"\[[^\[\]]*\]", " ", cleaned)
    cleaned = re.sub(r"\([^()]*\)", " ", cleaned)
    cleaned = re.sub(r"\{[^{}]*\}", " ", cleaned)
    cleaned = re.sub(r"<[^<>]*>", " ", cleaned)
    cleaned = re.sub(r"\s*/\s*", " ", cleaned)
    cleaned = re.sub(r"[*_`#~|]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.strip()


# --------------------------- local tone generator -----------------------------
def _tone_pcm(duration_sec: float, sr: int = 16000, freq: float = 440.0, amp: float = 0.7) -> bytes:
    import math

    frames = int(sr * duration_sec)
    a = max(0.0, min(1.0, amp))
    out = bytearray()
    for n in range(frames):
        x = a * math.sin(2 * math.pi * freq * n / sr)
        v = int(max(-1.0, min(1.0, x)) * 32767)
        out += v.to_bytes(2, "little", signed=True)
    return bytes(out)


# ---------------------------- WAV -> PCM extractor ----------------------------
def _wav_to_pcm_s16le_mono(wav_bytes: bytes) -> tuple[bytes, int]:
    with io.BytesIO(wav_bytes) as wav_io:
        with wave.open(wav_io, "rb") as wf:
            if wf.getnchannels() != 1:
                raise ValueError("need mono channel")
            if wf.getsampwidth() != 2:
                raise ValueError("need 16-bit PCM")
            if wf.getcomptype() != "NONE":
                raise ValueError("unsupported compression type")

            sample_rate = wf.getframerate()
            pcm_bytes = wf.readframes(wf.getnframes())
            return pcm_bytes, sample_rate


# --------------------------- OpenAI TTS integration ---------------------------
async def _openai_tts_sentence_pcm(
    sentence: str,
    sr: int = 16000,
    voice: str = "nova",
    model: Optional[str] = None,
    speed: Optional[float] = None,
) -> tuple[bytes, str, str]:
    key = os.getenv("OPENAI_API_KEY")
    if not key or OpenAI is None:
        dur = max(0.6, min(1.2, len(sentence) / 20.0))
        return _tone_pcm(dur, sr, freq=660.0, amp=0.7), "tone", "no_key_or_sdk"

    client = OpenAI(api_key=key)  # type: ignore
    tts_model = model or os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts")
    tts_speed = _resolve_tts_speed(speed)

    tmp = Path(tempfile.gettempdir()) / f"openai_tts_{os.getpid()}_{asyncio.get_event_loop().time():.6f}.wav"

    def _do_stream_to_wav() -> bytes:
        with client.audio.speech.with_streaming_response.create(  # type: ignore
            model=tts_model,
            voice=voice,
            input=sentence,
            speed=tts_speed,
            response_format="wav",
        ) as response:
            response.stream_to_file(str(tmp))
        data = tmp.read_bytes()
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        return data

    try:
        wav_bytes: bytes = await asyncio.to_thread(_do_stream_to_wav)
        pcm, got_sr = _wav_to_pcm_s16le_mono(wav_bytes)

        if got_sr != sr:
            import math

            ratio = got_sr / sr
            out = bytearray()
            frames_in = len(pcm) // 2
            for i in range(int(frames_in / ratio)):
                j = int(math.floor(i * ratio)) * 2
                if j + 1 < len(pcm):
                    out += pcm[j : j + 2]
            return bytes(out), "openai", "ok_resampled"

        return pcm, "openai", "ok"

    except Exception as e:
        dur = max(0.6, min(1.2, len(sentence) / 20.0))
        try:
            print(f"[TTS] OpenAI error: {type(e).__name__}: {e}")
        except Exception:
            pass
        return _tone_pcm(dur, sr, freq=440.0, amp=0.7), "tone", f"exc:{type(e).__name__}"


async def _openai_tts_wav(
    text: str,
    voice: str = "nova",
    model: Optional[str] = None,
    speed: Optional[float] = None,
) -> bytes:
    text = _prepare_text_for_tts(text)
    if not text:
        raise HTTPException(status_code=422, detail="text is empty after cleanup")

    key = os.getenv("OPENAI_API_KEY")
    if not key or OpenAI is None:
        raise HTTPException(status_code=503, detail="openai_tts_unavailable")

    client = OpenAI(api_key=key)  # type: ignore
    tts_model = model or os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts")
    tts_speed = _resolve_tts_speed(speed)
    tmp = (
        Path(tempfile.gettempdir())
        / f"openai_tts_wav_{os.getpid()}_{asyncio.get_event_loop().time():.6f}.wav"
    )

    def _do_stream_to_wav() -> bytes:
        with client.audio.speech.with_streaming_response.create(  # type: ignore
            model=tts_model,
            voice=voice,
            input=text,
            speed=tts_speed,
            response_format="wav",
        ) as response:
            response.stream_to_file(str(tmp))
        data = tmp.read_bytes()
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        return data

    return await asyncio.to_thread(_do_stream_to_wav)


# --------------------------- NDJSON stream generator --------------------------
async def _ndjson_stream(
    text: str,
    sr: int = 16000,
    voice: str = "nova",
    model: Optional[str] = None,
    speed: Optional[float] = None,
    device_mode: bool = False,
) -> AsyncGenerator[bytes, None]:
    init = {
        "type": "init",
        "content_type": "none" if device_mode else "audio/pcm",
        "sample_rate": sr,
        "channels": 1,
        "provider_hint": "device" if device_mode else "openai_or_tone",
        "build": TTS_BUILD,
    }
    yield (json.dumps(init) + "\n").encode("utf-8")

    for i, sent in enumerate(_split_sentences(text)):
        if device_mode:
            event = {
                "type": "chunk",
                "seq": i,
                "sentence": sent,
                "provider": "device",
                "provider_reason": "device",
                "pcm_b64": "",
                "duration_sec": None,
            }
            yield (json.dumps(event) + "\n").encode("utf-8")
        else:
            pcm, provider, reason = await _openai_tts_sentence_pcm(
                sent,
                sr=sr,
                voice=voice,
                model=model,
                speed=speed,
            )
            event = {
                "type": "chunk",
                "seq": i,
                "sentence": sent,
                "provider": provider,
                "provider_reason": reason,
                "pcm_b64": base64.b64encode(pcm).decode("ascii"),
                "duration_sec": round(len(pcm) / (sr * 2), 3),
            }
            yield (json.dumps(event) + "\n").encode("utf-8")

        await asyncio.sleep(0)

    yield (json.dumps({"type": "done"}) + "\n").encode("utf-8")


@router.post("/tts/stream")
async def tts_stream(
    payload: dict = Body(...),
    device: bool = Query(False, description="If true, send no PCM (client will do device TTS)"),
    voice: str = Query("nova", description="OpenAI TTS voice id"),
    model: Optional[str] = Query(None, description="Override OpenAI TTS model"),
    speed: Optional[float] = Query(None, description="OpenAI TTS speed (0.25 ~ 4.0)"),
):
    text = str(payload.get("text", "")).strip()
    if not text:
        return StreamingResponse(
            (line.encode("utf-8") for line in ['{"type":"error","error":"empty_text"}\n']),
            media_type="application/x-ndjson",
        )

    payload_speed = payload.get("speed")
    speed_value = speed
    if speed_value is None and payload_speed is not None:
        try:
            speed_value = float(payload_speed)
        except Exception:
            speed_value = None
    stream = _ndjson_stream(
        text,
        sr=16000,
        voice=voice,
        model=model,
        speed=speed_value,
        device_mode=device,
    )
    return StreamingResponse(stream, media_type="application/x-ndjson")


@router.post("/tts/speak")
async def tts_speak(payload: dict = Body(...)):
    text = _prepare_text_for_tts(str(payload.get("text", "")))
    voice = str(payload.get("voice", "nova")).strip() or "nova"
    model = str(payload.get("model", "gpt-4o-mini-tts")).strip() or "gpt-4o-mini-tts"
    speed_raw = payload.get("speed")
    speed: Optional[float] = None
    if speed_raw is not None:
        try:
            speed = float(speed_raw)
        except Exception:
            speed = None
    if not text:
        raise HTTPException(status_code=422, detail="text is required")

    wav_bytes = await _openai_tts_wav(text=text, voice=voice, model=model, speed=speed)
    return Response(content=wav_bytes, media_type="audio/wav")
