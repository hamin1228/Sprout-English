from __future__ import annotations

import importlib.util
import inspect
import multiprocessing as mp
import os
import platform
import sys
import threading
from abc import ABC, abstractmethod
from concurrent.futures import ProcessPoolExecutor, TimeoutError as FuturesTimeoutError
from concurrent.futures.process import BrokenProcessPool
from dataclasses import dataclass
from typing import Any, Optional


_QWEN_WORKER_MODEL_KEY: tuple[str, str, str, int, int] | None = None
_QWEN_WORKER_MODEL: Any = None


@dataclass
class TranscriptionResult:
    transcript: str
    segments: list[dict[str, Any]]
    provider: str
    model: str


class LocalSttProvider(ABC):
    name: str
    model_id: str

    @abstractmethod
    def runtime_ready(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    def transcribe(self, audio_path: str, language: Optional[str]) -> TranscriptionResult:
        raise NotImplementedError


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "no", "off"}


def _default_qwen_isolate_process() -> bool:
    fallback = platform.system().lower() == "darwin" and platform.machine().lower() in {"arm64", "aarch64"}
    return _env_bool("LOCAL_STT_QWEN_ISOLATE_PROCESS", fallback)


def _default_qwen_device_map() -> str:
    raw = (os.getenv("LOCAL_STT_QWEN_DEVICE_MAP") or "").strip()
    if raw:
        return raw
    if platform.system().lower() == "darwin" and platform.machine().lower() in {"arm64", "aarch64"}:
        return "cpu"
    return "auto"


def _default_qwen_dtype(device_map: str) -> str:
    raw = (os.getenv("LOCAL_STT_QWEN_DTYPE") or "").strip()
    if raw:
        return raw
    if device_map.lower() == "cpu":
        return "float32"
    return "float16"


def _qwen_runtime_config() -> tuple[str, str, int, int]:
    device_map = _default_qwen_device_map()
    dtype_name = _default_qwen_dtype(device_map)
    max_batch = int(os.getenv("LOCAL_STT_QWEN_MAX_BATCH", "1"))
    max_new_tokens = int(os.getenv("LOCAL_STT_QWEN_MAX_NEW_TOKENS", "2048"))
    return dtype_name, device_map, max_batch, max_new_tokens


def _patch_transformers_check_model_inputs() -> None:
    # qwen-asr 0.0.6 uses @check_model_inputs(), while current transformers
    # exposes check_model_inputs(func). Add compatibility shim before qwen_asr import.
    from transformers.utils import generic as transformers_generic

    check_func = getattr(transformers_generic, "check_model_inputs", None)
    if check_func is None:
        return

    try:
        sig = inspect.signature(check_func)
    except Exception:
        return

    if len(sig.parameters) != 1:
        return

    if getattr(check_func, "__name__", "") == "_compat_check_model_inputs":
        return

    def _compat_check_model_inputs(func=None):
        if func is None:
            def decorator(inner_func):
                return check_func(inner_func)
            return decorator
        return check_func(func)

    setattr(transformers_generic, "check_model_inputs", _compat_check_model_inputs)


def _normalize_qwen_language(language: Optional[str]) -> Optional[str]:
    value = (language or "").strip()
    if not value or value.lower() == "auto":
        return None

    mapping = {
        "ko": "Korean",
        "kr": "Korean",
        "korean": "Korean",
        "en": "English",
        "eng": "English",
        "english": "English",
        "ja": "Japanese",
        "jp": "Japanese",
        "japanese": "Japanese",
        "zh": "Chinese",
        "chinese": "Chinese",
    }
    return mapping.get(value.lower(), value)


def _extract_qwen_transcription(results: Any) -> tuple[str, list[dict[str, Any]]]:
    transcript = ""
    segments: list[dict[str, Any]] = []

    if isinstance(results, (list, tuple)) and results:
        first = results[0]
    else:
        first = results

    if isinstance(first, str):
        transcript = first.strip()
    elif isinstance(first, dict):
        transcript = str(first.get("text", "")).strip()
        segments = _normalize_segments(first.get("segments") or first.get("time_stamps"))
    elif first is not None:
        transcript = str(getattr(first, "text", "") or "").strip()
        raw_segments = getattr(first, "segments", None) or getattr(first, "time_stamps", None)
        segments = _normalize_segments(raw_segments)

    return transcript, segments


def _qwen_worker_transcribe(
    model_id: str,
    dtype_name: str,
    device_map: str,
    max_batch: int,
    max_new_tokens: int,
    audio_path: str,
    language: Optional[str],
) -> dict[str, Any]:
    global _QWEN_WORKER_MODEL, _QWEN_WORKER_MODEL_KEY

    key = (model_id, dtype_name, device_map, max_batch, max_new_tokens)
    if _QWEN_WORKER_MODEL is None or _QWEN_WORKER_MODEL_KEY != key:
        if importlib.util.find_spec("torch") is None:
            raise RuntimeError("torch_not_found_in_worker")
        if importlib.util.find_spec("qwen_asr") is None:
            raise RuntimeError("qwen_asr_not_found_in_worker")

        import torch
        _patch_transformers_check_model_inputs()
        from qwen_asr import Qwen3ASRModel

        dtype = getattr(torch, dtype_name, torch.float16)
        _QWEN_WORKER_MODEL = Qwen3ASRModel.from_pretrained(
            model_id,
            dtype=dtype,
            device_map=device_map,
            max_inference_batch_size=max_batch,
            max_new_tokens=max_new_tokens,
        )
        _QWEN_WORKER_MODEL_KEY = key

    results = _QWEN_WORKER_MODEL.transcribe(audio=audio_path, language=language)
    transcript, segments = _extract_qwen_transcription(results)
    return {
        "transcript": transcript,
        "segments": segments,
    }


class QwenAsrProvider(LocalSttProvider):
    def __init__(self) -> None:
        self.name = "qwen"
        self.model_id = os.getenv("LOCAL_STT_QWEN_MODEL", "Qwen/Qwen3-ASR-1.7B")
        self._model: Any = None
        self._lock = threading.Lock()
        self._executor_lock = threading.Lock()
        self._executor: ProcessPoolExecutor | None = None
        self._isolate_process = _default_qwen_isolate_process()
        self.preloaded = False
        self.last_runtime_error: Optional[str] = None

    @staticmethod
    def _patch_transformers_check_model_inputs() -> None:
        _patch_transformers_check_model_inputs()

    def runtime_ready(self) -> bool:
        if importlib.util.find_spec("torch") is None:
            self.last_runtime_error = "torch_not_found"
            return False

        if importlib.util.find_spec("qwen_asr") is None:
            self.last_runtime_error = "qwen_asr_not_found"
            return False

        try:
            self._patch_transformers_check_model_inputs()
            from qwen_asr import Qwen3ASRModel  # noqa: F401
            self.last_runtime_error = None
            return True
        except Exception as exc:
            self.last_runtime_error = f"{type(exc).__name__}:{exc}"
            return False

    def _ensure_executor(self) -> ProcessPoolExecutor:
        with self._executor_lock:
            if self._executor is None:
                self._executor = ProcessPoolExecutor(
                    max_workers=1,
                    mp_context=mp.get_context("spawn"),
                )
            return self._executor

    def _reset_executor(self) -> None:
        with self._executor_lock:
            executor = self._executor
            self._executor = None
        if executor is not None:
            executor.shutdown(wait=False, cancel_futures=True)

    def _ensure_model_loaded(self) -> None:
        if self._model is not None:
            return

        if not self.runtime_ready():
            qwen_spec = importlib.util.find_spec("qwen_asr")
            torch_spec = importlib.util.find_spec("torch")
            raise RuntimeError(
                "Qwen provider runtime is not installed. "
                "Install optional deps: pip install torch qwen-asr "
                f"(python={sys.executable}, qwen_asr={bool(qwen_spec)}, torch={bool(torch_spec)})"
            )

        import torch
        self._patch_transformers_check_model_inputs()
        from qwen_asr import Qwen3ASRModel

        dtype_name, device_map, max_batch, max_new_tokens = _qwen_runtime_config()
        dtype = getattr(torch, dtype_name, torch.float16)

        self._model = Qwen3ASRModel.from_pretrained(
            self.model_id,
            dtype=dtype,
            device_map=device_map,
            max_inference_batch_size=max_batch,
            max_new_tokens=max_new_tokens,
        )

    def _transcribe_isolated(self, audio_path: str, language: Optional[str]) -> TranscriptionResult:
        dtype_name, device_map, max_batch, max_new_tokens = _qwen_runtime_config()
        timeout_sec = int(os.getenv("LOCAL_STT_QWEN_TIMEOUT_SEC", "240"))

        for attempt in range(2):
            executor = self._ensure_executor()
            future = executor.submit(
                _qwen_worker_transcribe,
                self.model_id,
                dtype_name,
                device_map,
                max_batch,
                max_new_tokens,
                audio_path,
                language,
            )
            try:
                payload = future.result(timeout=timeout_sec)
                self.last_runtime_error = None
                self.preloaded = True
                return TranscriptionResult(
                    transcript=str(payload.get("transcript", "")).strip(),
                    segments=list(payload.get("segments") or []),
                    provider=self.name,
                    model=self.model_id,
                )
            except FuturesTimeoutError as exc:
                future.cancel()
                self.last_runtime_error = f"qwen_worker_timeout:{timeout_sec}s"
                raise RuntimeError(self.last_runtime_error) from exc
            except BrokenProcessPool as exc:
                self.last_runtime_error = "qwen_worker_crashed"
                self._reset_executor()
                if attempt == 0:
                    continue
                raise RuntimeError(
                    "qwen_worker_crashed. Try safer settings: "
                    "LOCAL_STT_QWEN_DEVICE_MAP=cpu LOCAL_STT_QWEN_DTYPE=float32"
                ) from exc
            except Exception as exc:
                self.last_runtime_error = f"qwen_worker_failed:{type(exc).__name__}:{exc}"
                raise RuntimeError(self.last_runtime_error) from exc

        raise RuntimeError("qwen_worker_crashed")

    def transcribe(self, audio_path: str, language: Optional[str]) -> TranscriptionResult:
        language_norm = self._normalize_language(language)

        if self._isolate_process:
            return self._transcribe_isolated(audio_path=audio_path, language=language_norm)

        with self._lock:
            self._ensure_model_loaded()
            results = self._model.transcribe(audio=audio_path, language=language_norm)
            self.preloaded = True

        transcript, segments = _extract_qwen_transcription(results)
        return TranscriptionResult(
            transcript=transcript,
            segments=segments,
            provider=self.name,
            model=self.model_id,
        )

    @staticmethod
    def _normalize_language(language: Optional[str]) -> Optional[str]:
        return _normalize_qwen_language(language)


def _normalize_segments(raw: Any) -> list[dict[str, Any]]:
    if not raw:
        return []

    normalized: list[dict[str, Any]] = []
    for item in raw:
        if isinstance(item, dict):
            start = item.get("start")
            end = item.get("end")
            text = item.get("text", "")
        else:
            start = getattr(item, "start", None)
            end = getattr(item, "end", None)
            text = getattr(item, "text", "")

        if start is None or end is None:
            continue

        try:
            normalized.append(
                {
                    "start_ms": int(float(start) * 1000),
                    "end_ms": int(float(end) * 1000),
                    "text": str(text or "").strip(),
                }
            )
        except Exception:
            continue

    return normalized
