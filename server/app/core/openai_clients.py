from __future__ import annotations

from openai import AsyncOpenAI, OpenAI

_sync_client: OpenAI | None = None
_async_client: AsyncOpenAI | None = None


def get_sync_client() -> OpenAI:
    global _sync_client
    if _sync_client is None:
        _sync_client = OpenAI()
    return _sync_client


def get_async_client() -> AsyncOpenAI:
    global _async_client
    if _async_client is None:
        _async_client = AsyncOpenAI()
    return _async_client
