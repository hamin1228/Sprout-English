"""
Rate limiting utilities for FastAPI (Sliding Window, asyncio-safe)
------------------------------------------------------------------
목적:
  - UID/IP 기준 분당 요청 수를 제한하기 위한 경량 유틸리티.
  - HTTP(REST)와 WebSocket 모두에서 동일한 로직 사용.

핵심 특징(보고서 요약):
  - Sliding Window 알고리즘: 윈도우 내 타임스탬프를 덱(deque)에 보관/정리 → 부드러운 제한.
  - 시간 기준: time.monotonic() 사용 → 시스템 시계 변경 영향 최소화.
  - 동시성: asyncio.Lock으로 동일 프로세스 내 경쟁상태 방지.
  - 분리 버킷: UID(로그인/디바이스 식별)와 IP를 독립적으로 관리.
  - 예외 모델: 초과 시 HTTP 429(Too Many Requests)와 남은 대기시간(reset_in_sec)을 구조화 응답.

사용 예시(요약):
  - REST 라우트: await limiter.check_http(request)
  - WS 핸들러: await limiter.check_ws(uid, ip)
"""
from __future__ import annotations
import time
import asyncio
from typing import Dict, Deque, Optional
# [NEW] defaultdict 추가: SimpleRateLimiter에서 IP별 버킷 관리용
from collections import deque, defaultdict

from fastapi import Request, HTTPException, status

# [NEW] __all__ 확장: SimpleRateLimiter / speech_turn_rate_limiter 공개
__all__ = ["RateLimitExceeded", "SlidingWindow", "RateLimiter", "SimpleRateLimiter", "speech_turn_rate_limiter"]

class RateLimitExceeded(HTTPException):
    """HTTP 429 예외.
    - detail 페이로드는 {"error":"rate_limited","reset_in_sec":<float>} 형태로 직렬화됨.
    - REST/WS 공통으로 사용 가능(WS에선 코드/메시지 변환 후 전송하기도 함).
    """
    def __init__(self, reset_in: float):
        super().__init__(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={"error": "rate_limited", "reset_in_sec": round(reset_in, 3)},
        )

class SlidingWindow:
    """고정 윈도우가 아닌 슬라이딩 윈도우 카운터.
    - 덱(deque)에 이벤트 발생 시각들을 보관하고, 윈도우 밖 값을 제거하며 카운트합니다.
    - 시간 계산은 time.monotonic() 기반으로 시스템 시계 변경의 영향을 받지 않습니다.
    - 단일 인스턴스는 스레드/코루틴 세이프가 아니므로 RateLimiter에서 Lock으로 감싸 사용합니다.
    """
    def __init__(self, limit: int, window_sec: int = 60):
        # 허용 횟수(limit)와 윈도우 크기(초). 예: 60회/분
        self.limit = limit
        self.window_sec = window_sec
        # 최근 이벤트 시각(초, monotonic 기준)을 보관하는 덱
        self.events: Deque[float] = deque()

    def check_and_add(self) -> float:
        """허용되면 0.0, 초과되면 '다음 허용까지 남은 초'를 리턴.
        - 슬라이딩 윈도우: 현재 시각에서 window_sec을 넘어선 과거 이벤트를 제거한 후 개수를 비교.
        - 암묵적 복잡도: 이벤트 한 건당 amortized O(1) (덱 앞에서만 pop되기 때문).
        """
        now = time.monotonic()
        w = self.window_sec

        # 1) 윈도우 밖(현재-윈도우 초 보다 오래된) 이벤트들을 제거
        while self.events and now - self.events[0] > w:
            self.events.popleft()

        # 2) 현재 윈도우 내 이벤트 개수가 limit 이상이면 거부
        if len(self.events) >= self.limit:
            # 가장 오래된 이벤트가 윈도우를 벗어날 때까지 남은 시간
            reset_in = w - (now - self.events[0])
            return reset_in

        # 3) 허용 → 현재 이벤트 타임스탬프 기록
        self.events.append(now)
        return 0.0

class RateLimiter:
    """UID/IP 기준 슬라이딩 윈도우 레이트리미터(프로세스 내 공유).
    - UID가 있을 경우 UID 버킷을, 없으면 IP 버킷을 사용해 공정성을 확보합니다.
    - asyncio.Lock으로 임계 구간을 보호하여 동시 접근 시 일관성을 보장합니다.
    - 다중 프로세스/다중 인스턴스 환경에서는 외부 저장소(예: Redis)로의 확장이 필요합니다.
    기본 정책(프로젝트 가이드라인):
      * UID: 분당 60회
      * IP : 분당 6회
    """
    def __init__(self, uid_limit: int = 60, ip_limit: int = 6, window_sec: int = 60):
        # 각 키 스페이스별 버킷(슬라이딩 윈도우) 저장소
        self.uid_buckets: Dict[str, SlidingWindow] = {}
        self.ip_buckets: Dict[str, SlidingWindow] = {}
        # 정책 값
        self.uid_limit = uid_limit
        self.ip_limit = ip_limit
        self.window_sec = window_sec
        # 동시성 제어(프로세스 내): 동일 시점 다중 접근 보호
        self.lock = asyncio.Lock()

    async def check_http(self, request: Request):
        """HTTP 요청 레이트리밋 검사.
        - 헤더 X-UID 또는 쿼리 uid를 우선 사용, 없으면 요청 IP로 제한.
        - 초과 시 RateLimitExceeded(HTTP 429)를 발생시킵니다.
        """
        key_uid = request.headers.get("X-UID") or request.query_params.get("uid")
        ip = request.client.host if request.client else "unknown"

        # 임계 구간(버킷 접근/생성 + 카운팅)을 락으로 보호
        async with self.lock:
            if key_uid:
                bucket = self.uid_buckets.setdefault(key_uid, SlidingWindow(self.uid_limit, self.window_sec))
            else:
                bucket = self.ip_buckets.setdefault(ip, SlidingWindow(self.ip_limit, self.window_sec))
            reset_in = bucket.check_and_add()

        # 초과 시 429 반환(예외)
        if reset_in > 0:
            raise RateLimitExceeded(reset_in)

    async def check_ws(self, key_uid: Optional[str], ip: str):
        """WebSocket 연결/메시지 레이트리밋 검사.
        - WS 컨텍스트에선 이미 uid/ip를 알고 있다고 가정하여 인자로 받습니다.
        - 초과 시 RateLimitExceeded(HTTP 429)와 동일한 페이로드로 처리(상위에서 코드 매핑).
        """
        async with self.lock:
            if key_uid:
                bucket = self.uid_buckets.setdefault(key_uid, SlidingWindow(self.uid_limit, self.window_sec))
            else:
                bucket = self.ip_buckets.setdefault(ip, SlidingWindow(self.ip_limit, self.window_sec))
            reset_in = bucket.check_and_add()
        if reset_in > 0:
            raise RateLimitExceeded(reset_in)


# [NEW] /speech/turn 전용의 초간단 IP 기반 레이트리밋 구현(SimpleRateLimiter)
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