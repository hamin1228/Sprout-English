from __future__ import annotations

import io
import math
import re
import struct
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from fastapi import HTTPException, Request, UploadFile, status

from app.config_loader import settings
from app.core.logging import log

MAX_AUDIO_BYTES = 10 * 1024 * 1024
MAX_DURATION_S = 60
ALLOWED_WAV_MIME_TYPES = {
    "audio/wav", "audio/x-wav", "audio/wave",
    "audio/m4a", "audio/mp4", "audio/x-m4a",
    "audio/mpeg", "application/octet-stream",
}
DEFAULT_WHISPER_MODEL = ""
DEFAULT_OPENAI_TIMEOUT_S = 60
DEFAULT_STORAGE_LOCAL_PATH = "./app/storage"
DEFAULT_TTS_MODEL = "gpt-4o-mini-tts"
DEFAULT_TTS_VOICE = "nova"
DEFAULT_TTS_SPEED = "1.0"

_FILENAME_SAFE = re.compile("[^A-Za-z0-9._-]")


def _safe_filename(name: str) -> str:
    name = (name or "").strip()
    if not name:
        return "audio.wav"
    name = name.replace("\\", "/").split("/")[-1]
    return _FILENAME_SAFE.sub("_", name)


def _wav_duration_ms(data: bytes) -> int:
    import wave
    with wave.open(io.BytesIO(data)) as w:
        frames = w.getnframes()
        rate = w.getframerate() or 1
        return int(frames * 1000 / rate)


def _wav_signal_profile(data: bytes) -> Optional[Dict[str, float]]:
    import wave
    with wave.open(io.BytesIO(data)) as wav_file:
        sample_rate = wav_file.getframerate() or 1
        channels = wav_file.getnchannels() or 1
        sample_width = wav_file.getsampwidth()
        frame_count = wav_file.getnframes()
        if sample_width != 2 or frame_count <= 0:
            return None
        window_frames = min(frame_count, int(sample_rate * 1.5))
        raw = wav_file.readframes(window_frames)

    total_samples = len(raw) // sample_width
    if total_samples <= 0:
        return None

    unpacked = struct.unpack(f"<{total_samples}h", raw)
    mono_samples = unpacked[::channels]
    if len(mono_samples) < max(800, sample_rate // 8):
        return None

    peak = max(abs(s) for s in mono_samples) / 32768.0
    rms = math.sqrt(sum((s / 32768.0) ** 2 for s in mono_samples) / max(len(mono_samples), 1))
    clipped_ratio = sum(1 for s in mono_samples if abs(s) >= 32000) / max(len(mono_samples), 1)
    zero_crossings = sum(
        1 for i in range(1, len(mono_samples))
        if (mono_samples[i - 1] <= 0 < mono_samples[i]) or
           (mono_samples[i - 1] >= 0 > mono_samples[i])
    )
    duration_sec = len(mono_samples) / sample_rate
    tone_hz = zero_crossings / 2 / max(duration_sec, 0.001)
    return {
        "peak": round(peak, 4),
        "rms": round(rms, 4),
        "clipped_ratio": round(clipped_ratio, 4),
        "tone_hz": round(tone_hz, 1),
        "duration_ms": int(duration_sec * 1000),
    }


def _is_unstable_wav_signal(profile: Optional[Dict[str, float]]) -> bool:
    if not profile:
        return False
    if int(profile.get("duration_ms", 0)) < 800:
        return False
    peak = float(profile.get("peak", 0.0))
    rms = float(profile.get("rms", 0.0))
    clipped_ratio = float(profile.get("clipped_ratio", 0.0))
    tone_hz = float(profile.get("tone_hz", 0.0))
    looks_like_full_scale_tone = peak >= 0.98 and 0.68 <= rms <= 0.73 and 160.0 <= tone_hz <= 320.0
    looks_like_clipped_input = peak >= 0.99 and rms >= 0.55 and clipped_ratio >= 0.015
    return looks_like_full_scale_tone or looks_like_clipped_input


def cleanup_old_audio_files(directory: str, max_age_hours: int = 24) -> int:
    """directory 안에서 max_age_hours보다 오래된 파일을 삭제하고 삭제한 파일 수를 반환한다.

    임시 오디오 파일 전용으로만 사용할 것. 자동 실행되지 않으며 관리자가 직접 호출해야 한다.
    예: cleanup_old_audio_files("./app/storage/audio", max_age_hours=48)
    """
    base = Path(directory)
    if not base.exists():
        return 0
    cutoff = time.time() - max_age_hours * 3600
    deleted = 0
    for f in base.rglob("*"):
        if f.is_file() and f.stat().st_mtime < cutoff:
            try:
                f.unlink()
                deleted += 1
            except OSError:
                pass
    return deleted


async def validate_and_save_audio(file: UploadFile, request: Request) -> dict:
    trace_id = getattr(request.state, "trace_id", "-")
    raw = await file.read()
    if not raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "empty_file", "message": "파일이 비어 있습니다."},
        )
    if len(raw) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={"code": "too_large", "message": "파일 크기는 최대 10MB까지 허용됩니다."},
        )

    mime = (file.content_type or "").lower()
    duration_ms = None
    signal_profile = None
    try:
        ct = file.content_type or ""
        if not ct.startswith("audio/") and ct != "application/octet-stream":
            log.warning(f"Unsupported MIME type rejected: {ct}", trace_id=trace_id)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"code": "unsupported_format", "message": f"지원하지 않는 파일 형식입니다: {ct}"},
            )
        if mime in ALLOWED_WAV_MIME_TYPES or (raw[:4] == b"RIFF" and raw[8:12] == b"WAVE"):
            try:
                duration_ms = _wav_duration_ms(raw)
                signal_profile = _wav_signal_profile(raw)
                if duration_ms > MAX_DURATION_S * 1000:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail={"code": "file_too_long", "message": f"오디오가 너무 깁니다: {duration_ms}ms > {MAX_DURATION_S}초"},
                    )
            except HTTPException:
                raise
            except Exception:
                log.warning("WAV header parsing failed, but continuing", trace_id=trace_id)
        else:
            log.info(f"Non-WAV audio file detected ({ct}), skipping duration check", trace_id=trace_id)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "invalid_header", "message": "오디오 헤더를 해석할 수 없습니다."},
        )

    trace_id = getattr(request.state, "trace_id", None) or str(uuid.uuid4())
    base = Path(getattr(settings, "STORAGE_LOCAL_PATH", DEFAULT_STORAGE_LOCAL_PATH))
    day = datetime.utcnow().strftime("%Y%m%d")
    dest_dir = base / "audio" / day
    dest_dir.mkdir(parents=True, exist_ok=True)
    safe_name = _safe_filename(file.filename)
    dest_path = dest_dir / f"{trace_id}_{safe_name}"
    dest_path.write_bytes(raw)
    audio_url = "/static/" + dest_path.relative_to(base).as_posix()
    return {
        "trace_id": trace_id,
        "bytes": len(raw),
        "duration_ms": duration_ms,
        "audio_path": str(dest_path),
        "audio_url": audio_url,
        "mime": mime or "application/octet-stream",
        "original_filename": file.filename or "audio.wav",
        "signal_profile": signal_profile,
    }
