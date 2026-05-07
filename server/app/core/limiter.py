from __future__ import annotations

import os
import time
from collections import deque
from typing import Optional


def _env_int(name: str, default: int, minimum: int = 1) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return max(minimum, int(raw))
    except Exception:
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "no", "off"}


def _is_local_loopback_ip(ip: str) -> bool:
    return (ip or "").strip().lower() in {"127.0.0.1", "::1", "localhost"}


class _SlidingWindow:
    def __init__(self, limit: int, window_sec: int = 60):
        self.limit = limit
        self.window_sec = window_sec
        self.events: deque = deque()

    def check_and_add(self) -> float:
        now = time.monotonic()
        w = self.window_sec
        while self.events and now - self.events[0] > w:
            self.events.popleft()
        if len(self.events) >= self.limit:
            return w - (now - self.events[0])
        self.events.append(now)
        return 0.0


class _Limiter:
    def __init__(
        self,
        uid_limit: int = 60,
        ip_limit: int = 6,
        window_sec: int = 60,
        skip_local_ip: bool = False,
    ):
        self.uid_limit = uid_limit
        self.ip_limit = ip_limit
        self.window_sec = window_sec
        self.skip_local_ip = skip_local_ip
        self._uid: dict = {}
        self._ip: dict = {}

    def check(self, uid: Optional[str], ip: str) -> float:
        if self.skip_local_ip and _is_local_loopback_ip(ip):
            return 0.0
        if uid:
            bucket = self._uid.setdefault(uid, _SlidingWindow(self.uid_limit, self.window_sec))
        else:
            bucket = self._ip.setdefault(ip, _SlidingWindow(self.ip_limit, self.window_sec))
        return bucket.check_and_add()


# WebSocket chat 전용 레이트 리미터 (uid/IP 기반 슬라이딩 윈도우)
chat_limiter = _Limiter(
    uid_limit=_env_int("CHAT_WS_UID_LIMIT", 60),
    ip_limit=_env_int("CHAT_WS_IP_LIMIT", 6),
    window_sec=_env_int("CHAT_WS_WINDOW_SEC", 60),
    skip_local_ip=_env_bool("CHAT_WS_SKIP_LOCAL_IP", False),
)
