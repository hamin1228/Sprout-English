

from __future__ import annotations
import os
import re
from typing import List, Dict, Tuple, Optional

# OpenAI official Python SDK (v1+)
# Dependency: pip install openai
from openai import OpenAI

# Lazy-initialized OpenAI client (reads OPENAI_API_KEY from env)
_client: Optional[OpenAI] = None
_STT_ALLOWED_TEXT_RE = re.compile(r"[^A-Za-z0-9\s\u3131-\u318E\uAC00-\uD7A3.,!?;:'\"()\-%&/]+")
_STT_TRANSCRIBE_PROMPT = (
    "Transcribe only spoken English and Korean. "
    "Keep Korean and English code-switching exactly as spoken. "
    "Do not translate. Do not output words from other languages. "
    "If audio is unclear or sounds like noise, prefer omission over guessing."
)


def _get_client() -> OpenAI:
    """
    Create/return a singleton OpenAI client.
    - API key is taken from the environment variable OPENAI_API_KEY.
    - Optional timeout can be adjusted via OPENAI_TIMEOUT_S (default: 60s).
    """
    global _client
    if _client is None:
        timeout_s = float(os.getenv("OPENAI_TIMEOUT_S", "60"))
        _client = OpenAI(timeout=timeout_s)  # type: ignore[arg-type]
    return _client


def _normalize_ko_en_transcript(text: str) -> str:
    cleaned = _STT_ALLOWED_TEXT_RE.sub(" ", text or "")
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.strip()


def transcribe_file(path: str, language: str | None = None) -> Tuple[str, List[Dict]]:
    """
    Transcribe an audio file via OpenAI Whisper API.

    Args:
        path: Absolute or relative path to a local audio file (e.g., .wav).
        language: ISO 639-1 language code (e.g., "en", "ko"). If None, auto-detect.

    Returns:
        (transcript, segments)
        - transcript: str
        - segments: list of dicts [{start_ms, end_ms, text}, ...] if available.
          (When response_format='verbose_json' is supported.)
    """
    client = _get_client()

    # Choose model from env only. Local STT mode should bypass this path.
    model = (os.getenv("OPENAI_WHISPER_MODEL") or "").strip()
    if not model:
        raise RuntimeError("openai_stt_model_not_configured")

    # Base kwargs for the API call; omit 'language' to enable auto-detect
    kwargs: Dict = {"model": model}
    if language:
        kwargs["language"] = language
    kwargs["prompt"] = _STT_TRANSCRIBE_PROMPT

    # First try 'verbose_json' for segment details; fall back to default on error.
    try:
        with open(path, "rb") as f:
            resp = client.audio.transcriptions.create(  # type: ignore[attr-defined]
                file=f,
                response_format="verbose_json",
                **kwargs,
            )
    except Exception:
        with open(path, "rb") as f:
            resp = client.audio.transcriptions.create(  # type: ignore[attr-defined]
                file=f,
                **kwargs,
            )

    # Extract transcript text
    transcript = getattr(resp, "text", None)
    if transcript is None and isinstance(resp, dict):
        transcript = resp.get("text", "")
    if transcript is None:
        transcript = ""

    # Extract and normalize segments, if present
    segments_out: List[Dict] = []
    segs = getattr(resp, "segments", None)
    if segs is None and isinstance(resp, dict):
        segs = resp.get("segments")

    if segs:
        for s in segs:
            # Support attribute- and dict-like objects
            start = getattr(s, "start", None) if not isinstance(s, dict) else s.get("start")
            end = getattr(s, "end", None) if not isinstance(s, dict) else s.get("end")
            text = getattr(s, "text", None) if not isinstance(s, dict) else s.get("text", "")
            if start is None or end is None:
                continue
            try:
                segments_out.append(
                    {
                        "start_ms": int(float(start) * 1000),
                        "end_ms": int(float(end) * 1000),
                        "text": (text or "").strip(),
                    }
                )
            except Exception:
                # Skip malformed segment entries gracefully
                continue

    transcript = _normalize_ko_en_transcript(transcript)
    normalized_segments: List[Dict] = []
    for seg in segments_out:
        seg_text = _normalize_ko_en_transcript(str(seg.get("text", "")))
        if not seg_text:
            continue
        normalized_segments.append(
            {
                "start_ms": seg["start_ms"],
                "end_ms": seg["end_ms"],
                "text": seg_text,
            }
        )

    return transcript, normalized_segments
