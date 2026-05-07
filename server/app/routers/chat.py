from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from typing import List, Optional

from fastapi import APIRouter, Body, HTTPException, WebSocket, WebSocketDisconnect

from app.core.limiter import chat_limiter
from app.core.logging import log
from app.core.openai_clients import get_async_client

router = APIRouter()

_FREE_TALK_CHAT_SYSTEM_PROMPT = """You are the speaking partner in an English-learning free-talk app.

Default style:
- Sound like a casual but gentle English tutor, not a generic AI assistant.
- Be warm, natural, and conversational.
- Usually reply in 1 to 3 sentences.
- Keep the conversation moving with one simple follow-up question when appropriate.
- If the user says something unexpected, respond naturally instead of giving a long lecture.
- Do not over-explain unless the user explicitly asks for an explanation.

Conversation rules:
- Prefer natural spoken English.
- If the user uses Korean, you may briefly support them, but keep the main interaction focused on English practice.
- Do not use lists, headers, or textbook-style explanations in normal chat.
- Do not use parenthetical stage directions, slash-separated alternatives, or meta commentary.
- Avoid robotic phrases like "Let me explain that for you" unless the user directly asks.
- Keep answers short enough to feel like live conversation.
"""

_FREE_TALK_TRANSLATE_SYSTEM_PROMPT = """Translate the assistant's English reply into natural Korean.

Rules:
- Keep the tone gentle and conversational.
- Be concise and easy to read.
- Do not add explanations that were not in the original.
- Translate exactly the text you are given.
- Never answer the message.
- Never continue the conversation.
- Preserve whether the source is a question, statement, or short reaction.
- Return only the Korean translation text.
"""

FREE_TALK_CHAT_MODEL = os.getenv("FREE_TALK_CHAT_MODEL", "gpt-5-nano")
FREE_TALK_TRANSLATE_ENABLED = os.getenv("FREE_TALK_TRANSLATE_ENABLED", "1").strip().lower() not in {
    "0", "false", "no", "off",
}
_CHAT_STREAM_FRAGMENT_CHARS = max(1, int(os.getenv("CHAT_STREAM_FRAGMENT_CHARS", "12")))
_CHAT_STREAM_FRAGMENT_MIN_LEN = max(
    _CHAT_STREAM_FRAGMENT_CHARS + 1,
    int(os.getenv("CHAT_STREAM_FRAGMENT_MIN_LEN", "18")),
)
_CHAT_STREAM_FRAGMENT_DELAY_MS = max(0, int(os.getenv("CHAT_STREAM_FRAGMENT_DELAY_MS", "0")))


def _split_chat_stream_delta(text: str) -> List[str]:
    if not text:
        return []
    if len(text) < _CHAT_STREAM_FRAGMENT_MIN_LEN:
        return [text]
    return [text[i: i + _CHAT_STREAM_FRAGMENT_CHARS] for i in range(0, len(text), _CHAT_STREAM_FRAGMENT_CHARS)]


async def _translate_free_talk_reply(text: str) -> str:
    source = text.strip()
    if not source:
        return ""
    try:
        client = get_async_client()
        response = await client.chat.completions.create(
            model=os.getenv("OPENAI_TRANSLATE_MODEL", "gpt-5-nano"),
            messages=[
                {"role": "system", "content": _FREE_TALK_TRANSLATE_SYSTEM_PROMPT},
                {"role": "user", "content": f"Translate only the text inside <source> tags.\n<source>{source}</source>"},
            ],
            temperature=0.1,
        )
        content = (
            response.choices[0].message.content
            if response.choices and response.choices[0].message.content
            else ""
        )
        return str(content).strip()
    except Exception as e:
        log.error(f"Translate API error: {e}", trace_id="-")
        return ""


@router.websocket("/chat/stream")
async def chat_stream(ws: WebSocket):
    await ws.accept()
    uid: Optional[str] = ws.headers.get("X-UID") or ws.query_params.get("uid")
    ip = ws.client.host if ws.client else "unknown"
    reset = chat_limiter.check(uid, ip)
    if reset > 0:
        await ws.send_json({"type": "error", "error": "rate_limited", "reset_in_sec": round(reset, 3)})
        await ws.close(code=4408)
        return

    session_id = str(uuid.uuid4())
    await ws.send_json({"type": "init", "id": session_id, "model": FREE_TALK_CHAT_MODEL})

    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "error": "bad_json"})
                continue

            if msg.get("type") != "start" or "prompt" not in msg:
                await ws.send_json({"type": "error", "error": "expected_start"})
                continue

            prompt = str(msg["prompt"])
            trace_id = str(msg.get("trace_id") or session_id)
            history = msg.get("history") if isinstance(msg.get("history"), list) else []
            first_token_sent = False
            llm_started_at = time.perf_counter()

            messages = [{"role": "system", "content": _FREE_TALK_CHAT_SYSTEM_PROMPT}]
            for item in history[-12:]:
                if not isinstance(item, dict):
                    continue
                role = str(item.get("role") or "").strip()
                content = str(item.get("content") or "").strip()
                if role not in {"user", "assistant"} or not content:
                    continue
                messages.append({"role": role, "content": content})
            if not messages or messages[-1].get("role") != "user" or messages[-1].get("content") != prompt:
                messages.append({"role": "user", "content": prompt})

            client = get_async_client()
            try:
                assistant_chunks: list[str] = []
                stream = await client.chat.completions.create(
                    model=FREE_TALK_CHAT_MODEL,
                    messages=messages,
                    stream=True,
                )
                async for chunk in stream:
                    if chunk.choices[0].delta.content is not None:
                        content = chunk.choices[0].delta.content
                        fragments = _split_chat_stream_delta(content)
                        for i, fragment in enumerate(fragments):
                            if not first_token_sent:
                                first_token_sent = True
                                first_token_ms = int((time.perf_counter() - llm_started_at) * 1000)
                                log.info("chat_stream llm_first_token_ms=%s trace_id=%s", first_token_ms, trace_id)
                            assistant_chunks.append(fragment)
                            await ws.send_json({"type": "delta", "text": fragment})
                            if _CHAT_STREAM_FRAGMENT_DELAY_MS > 0 and len(fragments) > 1 and i < len(fragments) - 1:
                                await asyncio.sleep(_CHAT_STREAM_FRAGMENT_DELAY_MS / 1000.0)

                await ws.send_json({"type": "done"})
                if FREE_TALK_TRANSLATE_ENABLED:
                    translation = await _translate_free_talk_reply("".join(assistant_chunks))
                    if translation:
                        await ws.send_json({"type": "translation", "translation": translation})
            except Exception as e:
                log.error(f"OpenAI API error: {e}", trace_id=trace_id)
                await ws.send_json({"type": "error", "error": "llm_error"})

    except WebSocketDisconnect:
        return
    except Exception as e:
        log.error(f"WebSocket error: {e}", trace_id="-")
        try:
            await ws.send_json({"type": "error", "error": "internal_error"})
        finally:
            await ws.close(code=1011)


@router.post("/chat/translate")
async def chat_translate(payload: dict = Body(...)):
    text = str(payload.get("text", "")).strip()
    if not text:
        raise HTTPException(status_code=422, detail="text is required")
    translation = await _translate_free_talk_reply(text)
    if not translation:
        raise HTTPException(status_code=502, detail="translation_error")
    return {"translation": translation}
