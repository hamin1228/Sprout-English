# FILE: english_ai/server/app/middleware.py
from __future__ import annotations
import time
from typing import Callable
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.rate_limit import RateLimiter
from app.db import get_session
from app.usage import record_usage

def _client_ip(req: Request) -> str:
    # 프록시 사용 시 X-Forwarded-For 고려 가능
    return req.client.host if req.client else "unknown"

class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, limiter: RateLimiter):
        super().__init__(app)
        self.limiter = limiter

    async def dispatch(self, request: Request, call_next: Callable):
        # 헬스체크는 통과
        if request.url.path in ("/healthz",):
            return await call_next(request)
        # 레이트리밋
        await self.limiter.check_http(request)
        start = time.perf_counter()
        response: Response = await call_next(request)
        # 간단한 사용량 기록(HTTP) - 엔드포인트에서 세부값을 state에 넣어주면 더 정확
        try:
            tokens_in = int(getattr(request.state, "tokens_in", 0))
            tokens_out = int(getattr(request.state, "tokens_out", 0))
            cost = getattr(request.state, "cost_usd", None)
            uid = request.headers.get("X-UID") or request.query_params.get("uid")
            ip = _client_ip(request)
            latency_ms = int((time.perf_counter() - start) * 1000)
            async with get_session() as s:
                await record_usage(
                    s,
                    route=request.url.path,
                    uid=uid,
                    ip=ip,
                    tokens_in=tokens_in,
                    tokens_out=tokens_out,
                    cost_usd=cost,
                    latency_ms=latency_ms,
                    extra={"status_code": response.status_code},
                )
        except Exception:
            # 로깅 실패는 무시(서비스 영향 최소화)
            pass
        return response