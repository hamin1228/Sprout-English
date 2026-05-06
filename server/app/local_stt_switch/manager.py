from __future__ import annotations

import os
import sys
import tempfile
import threading
import time
import wave
from typing import Any, Optional

from .providers import QwenAsrProvider, TranscriptionResult


class LocalSttManager:
    def __init__(self) -> None:
        self._providers = {
            "qwen": QwenAsrProvider(),
        }
        self._state_lock = threading.Lock()
        self._active_provider = "qwen"
        self._active_language = os.getenv("LOCAL_STT_ACTIVE_LANGUAGE", "en").strip().lower() or "en"
        self._warmup_lock = threading.Lock()
        self._warmup_results: dict[str, dict[str, Any]] = {}

    @property
    def active_provider(self) -> str:
        with self._state_lock:
            return self._active_provider

    @property
    def active_language(self) -> str:
        with self._state_lock:
            return self._active_language

    def list_status(self) -> dict[str, Any]:
        with self._state_lock:
            active_provider = self._active_provider
            active_language = self._active_language
        with self._warmup_lock:
            warmups = dict(self._warmup_results)

        providers: list[dict[str, Any]] = []
        for key, provider in self._providers.items():
            ready = provider.runtime_ready()
            providers.append(
                {
                    "id": key,
                    "model": provider.model_id,
                    "runtime_ready": ready,
                    "runtime_error": getattr(provider, "last_runtime_error", None),
                    "preloaded": bool(getattr(provider, "preloaded", False)),
                    "warmup": warmups.get(key),
                    "active": key == active_provider,
                }
            )

        return {
            "active_provider": active_provider,
            "active_language": active_language,
            "python_executable": sys.executable,
            "providers": providers,
        }

    def set_active_provider(self, provider: str, language: Optional[str] = None) -> dict[str, Any]:
        normalized = (provider or "").strip().lower()
        if normalized not in self._providers:
            raise ValueError(f"unsupported_provider:{provider}")

        lang = (language or "").strip().lower()
        with self._state_lock:
            self._active_provider = normalized
            if lang:
                self._active_language = lang

        if _env_bool("LOCAL_STT_PRELOAD_ON_SWITCH", True):
            self.warmup_provider(provider=normalized, language=lang or None)

        return self.list_status()

    def transcribe(self, audio_path: str, provider: Optional[str], language: Optional[str]) -> TranscriptionResult:
        provider_name = (provider or "").strip().lower()
        with self._state_lock:
            selected_provider = provider_name or self._active_provider
            selected_language = (language or "").strip().lower() or self._active_language

        if selected_provider not in self._providers:
            raise ValueError(f"unsupported_provider:{selected_provider}")

        return self._providers[selected_provider].transcribe(audio_path=audio_path, language=selected_language)

    def preload_startup(self) -> dict[str, Any]:
        if not _env_bool("LOCAL_STT_PRELOAD_ON_STARTUP", True):
            return {
                "enabled": False,
                "providers": [],
            }

        providers = self._resolve_preload_providers()
        language = os.getenv("LOCAL_STT_PRELOAD_LANGUAGE", "").strip().lower() or None
        results: list[dict[str, Any]] = []
        for provider in providers:
            results.append(self.warmup_provider(provider=provider, language=language))

        return {
            "enabled": True,
            "providers": results,
        }

    def warmup_provider(self, provider: str, language: Optional[str] = None) -> dict[str, Any]:
        normalized = (provider or "").strip().lower()
        if normalized not in self._providers:
            raise ValueError(f"unsupported_provider:{provider}")

        with self._state_lock:
            default_language = self._active_language

        selected_language = (language or "").strip().lower() or default_language
        started_at = time.perf_counter()
        tmp_path = _create_silence_wav(duration_ms=700, sample_rate=16000)
        error: Optional[str] = None

        try:
            self._providers[normalized].transcribe(audio_path=tmp_path, language=selected_language)
        except Exception as exc:
            error = f"{type(exc).__name__}:{exc}"
        finally:
            try:
                os.unlink(tmp_path)
            except FileNotFoundError:
                pass

        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        result = {
            "ok": error is None,
            "elapsed_ms": elapsed_ms,
            "language": selected_language,
            "error": error,
            "at_unix_ms": int(time.time() * 1000),
        }
        with self._warmup_lock:
            self._warmup_results[normalized] = result
        return result

    def _resolve_preload_providers(self) -> list[str]:
        return ["qwen"]


def _create_silence_wav(duration_ms: int, sample_rate: int) -> str:
    fd, path = tempfile.mkstemp(prefix="local_stt_warmup_", suffix=".wav")
    os.close(fd)

    frames = max(1, int(sample_rate * duration_ms / 1000))
    silence = b"\x00\x00" * frames
    with wave.open(path, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(silence)
    return path


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() not in {"0", "false", "no", "off"}
