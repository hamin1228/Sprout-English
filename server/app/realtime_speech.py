from __future__ import annotations

import asyncio
import base64
import binascii
import json
import logging
import os
import tempfile
import time
import uuid
import wave
from typing import Any, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

import websockets

from app.services.stt import transcribe_file

log = logging.getLogger("app.realtime_speech")
NO_SPEECH_GRACE_MS = 1500
FINAL_TRANSCRIPT_TIMEOUT_MS = 4000
PCM_SAMPLE_RATE = 24000
PCM_CHANNELS = 1
PCM_SAMPLE_WIDTH = 2
MIN_FALLBACK_AUDIO_MS = 350
REALTIME_TRANSCRIBE_MODE = os.getenv(
    "OPENAI_REALTIME_TRANSCRIBE_MODE",
    "buffered",
).strip().lower()

REALTIME_TRANSCRIBE_MODEL = os.getenv(
    "OPENAI_REALTIME_TRANSCRIBE_MODEL",
    "",
).strip()
REALTIME_TRANSCRIBE_FALLBACK_MODELS = tuple(
    model.strip()
    for model in os.getenv("OPENAI_REALTIME_TRANSCRIBE_FALLBACK_MODELS", "").split(",")
    if model.strip()
)
REALTIME_TRANSCRIBE_PROMPT = (
    "Transcribe the audio exactly as spoken. Preserve Korean-English code-switching, "
    "do not translate, keep numbers, names, contractions, and mixed-language phrasing."
)


def _realtime_transcribe_model_candidates() -> list[str]:
    models: list[str] = []
    for model in (REALTIME_TRANSCRIBE_MODEL, *REALTIME_TRANSCRIBE_FALLBACK_MODELS):
        normalized = model.strip()
        if normalized and normalized not in models:
            models.append(normalized)
    return models


def _should_try_realtime_models() -> bool:
    return REALTIME_TRANSCRIBE_MODE in {"auto", "realtime"}


def register_realtime_speech_routes(app: FastAPI) -> None:
    @app.websocket("/speech/realtime")
    async def speech_realtime(ws: WebSocket):
        await ws.accept()

        trace_id = str(uuid.uuid4())
        started_at = time.perf_counter()
        openai_ws: Optional[Any] = None
        openai_pump_task: Optional[asyncio.Task[None]] = None
        session_started = False
        speech_started = False
        stop_requested = False
        final_transcript_sent = False
        final_transcript_text = ""
        active_model = REALTIME_TRANSCRIBE_MODEL
        fallback_batch_mode = False
        buffered_audio = bytearray()
        timings: dict[str, int] = {}
        transcript_terminal_event = asyncio.Event()

        async def send_client(payload: dict[str, Any]) -> None:
            if ws.client_state.name == "CONNECTED":
                await ws.send_json(payload)

        def mark_timing(key: str) -> None:
            if key not in timings:
                timings[key] = int((time.perf_counter() - started_at) * 1000)
                log.info(
                    "realtime_speech %s trace_id=%s value_ms=%s",
                    key,
                    trace_id,
                    timings[key],
                )

        async def close_openai() -> None:
            nonlocal openai_ws
            if openai_pump_task is not None:
                openai_pump_task.cancel()
                try:
                    await openai_pump_task
                except BaseException:
                    pass
            if openai_ws is not None:
                try:
                    await openai_ws.close()
                except Exception:
                    pass
                openai_ws = None

        def buffered_audio_duration_ms() -> int:
            bytes_per_second = PCM_SAMPLE_RATE * PCM_CHANNELS * PCM_SAMPLE_WIDTH
            if bytes_per_second <= 0:
                return 0
            return int(len(buffered_audio) * 1000 / bytes_per_second)

        async def transcribe_buffered_audio() -> tuple[str, list[dict[str, Any]]]:
            if buffered_audio_duration_ms() < MIN_FALLBACK_AUDIO_MS:
                return "", []

            fd, path = tempfile.mkstemp(suffix=".wav", prefix="freetalk_stt_")
            os.close(fd)
            try:
                with wave.open(path, "wb") as wav_file:
                    wav_file.setnchannels(PCM_CHANNELS)
                    wav_file.setsampwidth(PCM_SAMPLE_WIDTH)
                    wav_file.setframerate(PCM_SAMPLE_RATE)
                    wav_file.writeframes(bytes(buffered_audio))
                return await asyncio.to_thread(transcribe_file, path, None)
            finally:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass

        async def handle_openai_events() -> None:
            nonlocal speech_started, final_transcript_sent, final_transcript_text
            assert openai_ws is not None
            async for raw in openai_ws:
                try:
                    event = json.loads(raw)
                except Exception:
                    continue

                event_type = event.get("type", "")
                if event_type == "input_audio_buffer.speech_started":
                    speech_started = True
                    mark_timing("speech_started_ms")
                    await send_client({"type": "speech_started", "trace_id": trace_id})
                elif event_type == "input_audio_buffer.speech_stopped":
                    mark_timing("speech_stopped_ms")
                    await send_client({"type": "speech_stopped", "trace_id": trace_id})
                elif event_type == "conversation.item.input_audio_transcription.delta":
                    if event.get("delta"):
                        speech_started = True
                    mark_timing("first_transcript_delta_ms")
                    await send_client(
                        {
                            "type": "transcript_delta",
                            "trace_id": trace_id,
                            "item_id": event.get("item_id"),
                            "text": event.get("delta", ""),
                        }
                    )
                elif event_type == "conversation.item.input_audio_transcription.completed":
                    final_transcript_text = (event.get("transcript", "") or "").strip()
                    if final_transcript_text:
                        speech_started = True
                    final_transcript_sent = True
                    transcript_terminal_event.set()
                    mark_timing("final_transcript_ms")
                    await send_client(
                        {
                            "type": "transcript_final",
                            "trace_id": trace_id,
                            "item_id": event.get("item_id"),
                            "text": event.get("transcript", "") or "",
                            "usage": event.get("usage"),
                        }
                    )
                    if stop_requested:
                        break
                elif event_type == "error":
                    transcript_terminal_event.set()
                    await send_client(
                        {
                            "type": "error",
                            "trace_id": trace_id,
                            "error": event.get("error", {}).get("message", "realtime_error"),
                        }
                    )
                    break

        async def start_openai_session() -> None:
            nonlocal openai_ws, openai_pump_task, session_started, active_model, fallback_batch_mode
            api_key = os.getenv("OPENAI_API_KEY")
            if not api_key:
                await send_client(
                    {
                        "type": "error",
                        "trace_id": trace_id,
                        "error": "missing_openai_api_key",
                    }
                )
                return

            if not _should_try_realtime_models():
                fallback_batch_mode = True
                active_model = "audio-transcriptions-fallback"
                log.info(
                    "realtime transcription disabled by mode=%s trace_id=%s",
                    REALTIME_TRANSCRIBE_MODE,
                    trace_id,
                )
                session_started = True
                await send_client(
                    {
                        "type": "ready",
                        "trace_id": trace_id,
                        "model": active_model,
                        "mode": "buffered_fallback",
                    }
                )
                return

            last_exc: Optional[Exception] = None
            tried_models: list[str] = []

            for candidate_model in _realtime_transcribe_model_candidates():
                tried_models.append(candidate_model)
                try:
                    url = f"wss://api.openai.com/v1/realtime?model={candidate_model}"
                    openai_ws = await websockets.connect(
                        url,
                        additional_headers={
                            "Authorization": f"Bearer {api_key}",
                        },
                        max_size=None,
                        ping_interval=20,
                        ping_timeout=20,
                        open_timeout=15,
                    )

                    session_update = {
                        "type": "session.update",
                        "session": {
                            "type": "transcription",
                            "model": candidate_model,
                            "audio": {
                                "input": {
                                    "format": {
                                        "type": "audio/pcm",
                                        "rate": 24000,
                                    },
                                    "noise_reduction": {
                                        "type": "near_field",
                                    },
                                    "transcription": {
                                        "model": candidate_model,
                                        "prompt": REALTIME_TRANSCRIBE_PROMPT,
                                    },
                                    "turn_detection": {
                                        "type": "server_vad",
                                        "threshold": 0.5,
                                        "prefix_padding_ms": 300,
                                        "silence_duration_ms": 500,
                                    },
                                }
                            },
                            "include": ["item.input_audio_transcription.logprobs"],
                        },
                    }
                    await openai_ws.send(json.dumps(session_update))
                    active_model = candidate_model
                    last_exc = None
                    break
                except Exception as exc:
                    last_exc = exc
                    log.warning(
                        "realtime transcription model rejected model=%s error=%s",
                        candidate_model,
                        exc,
                    )
                    if openai_ws is not None:
                        try:
                            await openai_ws.close()
                        except Exception:
                            pass
                        openai_ws = None
                    if "invalid_model" not in str(exc) and "missing_model" not in str(exc):
                        break

            if openai_ws is None or last_exc is not None:
                fallback_batch_mode = True
                active_model = "audio-transcriptions-fallback"
                log.warning(
                    "realtime transcription unavailable, falling back to buffered transcription trace_id=%s tried=%s error=%s",
                    trace_id,
                    ", ".join(tried_models),
                    last_exc,
                )

            if not fallback_batch_mode:
                openai_pump_task = asyncio.create_task(handle_openai_events())
            session_started = True
            await send_client(
                {
                    "type": "ready",
                    "trace_id": trace_id,
                    "model": active_model,
                    "mode": "buffered_fallback" if fallback_batch_mode else "realtime",
                }
            )

        try:
            while True:
                raw = await ws.receive_text()
                try:
                    message = json.loads(raw)
                except Exception:
                    await send_client(
                        {
                            "type": "error",
                            "trace_id": trace_id,
                            "error": "bad_json",
                        }
                    )
                    continue

                msg_type = message.get("type")
                if msg_type == "start_session":
                    if not session_started:
                        await start_openai_session()
                elif msg_type == "audio_chunk":
                    audio_b64 = str(message.get("audio", "")).strip()
                    if not audio_b64:
                        continue
                    try:
                        chunk = base64.b64decode(audio_b64, validate=True)
                    except (binascii.Error, ValueError):
                        continue
                    mark_timing("first_audio_chunk_ms")
                    buffered_audio.extend(chunk)
                    if openai_ws is not None and not fallback_batch_mode:
                        await openai_ws.send(
                            json.dumps(
                                {
                                    "type": "input_audio_buffer.append",
                                    "audio": audio_b64,
                                }
                            )
                        )
                elif msg_type == "stop_session":
                    stop_requested = True
                    if openai_ws is not None and not fallback_batch_mode:
                        try:
                            await openai_ws.send(
                                json.dumps({"type": "input_audio_buffer.commit"})
                            )
                        except Exception:
                            pass
                    if not speech_started and not final_transcript_sent:
                        await asyncio.sleep(NO_SPEECH_GRACE_MS / 1000)
                    if not final_transcript_sent and not final_transcript_text:
                        try:
                            await asyncio.wait_for(
                                transcript_terminal_event.wait(),
                                timeout=FINAL_TRANSCRIPT_TIMEOUT_MS / 1000,
                            )
                        except asyncio.TimeoutError:
                            pass
                    if (
                        not speech_started
                        and not final_transcript_sent
                        and not final_transcript_text
                    ):
                        if fallback_batch_mode:
                            transcript, segments = await transcribe_buffered_audio()
                            final_text = (transcript or "").strip()
                            if final_text:
                                final_transcript_sent = True
                                final_transcript_text = final_text
                                mark_timing("final_transcript_ms")
                                await send_client(
                                    {
                                        "type": "transcript_final",
                                        "trace_id": trace_id,
                                        "item_id": None,
                                        "text": final_text,
                                        "usage": None,
                                        "segments": segments,
                                    }
                                )
                            else:
                                await send_client(
                                    {
                                        "type": "error",
                                        "trace_id": trace_id,
                                        "error": "no_speech_detected",
                                    }
                                )
                            break
                        await send_client(
                            {
                                "type": "error",
                                "trace_id": trace_id,
                                "error": "no_speech_detected",
                            }
                        )
                        break
                elif msg_type == "cancel_session":
                    break
        except WebSocketDisconnect:
            pass
        finally:
            await close_openai()
            try:
                await ws.close()
            except Exception:
                pass
