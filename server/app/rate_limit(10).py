# server/app/rate_limit.py
from __future__ import annotations

import time
from collections import defaultdict, deque
from typing import Deque, Dict


class SimpleRateLimiter:
    """
    매우 단순한 IP 기반 레이트 리미터.
    - key: 보통 클라이언트 IP
    - window_sec 동안 max_requests 이상이면 차단
    """
    def __init__(self, max_requests: int, window_sec: int) -> None:
        self.max_requests = max_requests
        self.window_sec = window_sec
        self._buckets: Dict[str, Deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = time.time()
        dq = self._buckets[key]
        cutoff = now - self.window_sec

        # 오래된 타임스탬프 제거
        while dq and dq[0] < cutoff:
            dq.popleft()

        if len(dq) >= self.max_requests:
            return False

        dq.append(now)
        return True


# /speech/turn에 적용할 기본 정책: 60초에 10회
speech_turn_rate_limiter = SimpleRateLimiter(max_requests=10, window_sec=60)