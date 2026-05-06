"""
WebSocket Route: /chat/stream (Delta Streaming for AI English App)
---------------------------------------------------------------
목적(Purpose)
- Git 없이도 바로 테스트 가능한 **경량 WS 토큰 스트리밍** 구현입니다.
- 클라이언트-서버 간 **init/delta/done 계약**을 명확히 하고, 운영 진단을 위해
  토큰/비용/지연(latency)을 로깅할 수 있게 설계했습니다.

프로토콜(Protocol)
- C→S: {"type":"start","prompt":"..."}
- S→C: {"type":"init","id":"<uuid>","model":"gpt-5-nano"}
- S→C: {"type":"delta","index":<n>,"text":"..."} * n
- S→C: {"type":"done"}
- 오류 시: {"type":"error","error":"bad_json|expected_start|rate_limited|internal_error"}

운영 포인트(Ops)
- **레이트리밋**: UID 분당 60회, IP 분당 6회(기본). 초과 시 4408으로 종료.
- **사용량 기록**: tokens_in/out, cost_usd(러프하게 단가 가정), latency_ms.
- **지연 제어**: 80ms 간격으로 delta를 전송해 UX상 스트리밍 체감을 제공합니다.
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.websockets import WebSocketState

from app.rate_limit import RateLimiter, RateLimitExceeded
from app.db import get_session
from app.usage import record_usage


def _estimate_tokens(text: str) -> int:
    """아주 러프한 토큰 근사(영문 기준).
    - 가정: 1 토큰 ~= 4 chars
    - 용도: 사용량/비용 대략치 산정(로그/리포트)
    """
    return max(1, len(text) // 4)


async def register_ws_routes(app: FastAPI, limiter: RateLimiter):
    """FastAPI 앱에 **/chat/stream** WS 라우트를 동적으로 등록.
    - `app.websocket("/chat/stream")` 데코레이터를 내부에 정의해 바인딩합니다.
    - `limiter`는 UID/IP 기준 슬라이딩 윈도우 레이트리밋을 제공합니다.
    """

    @app.websocket("/chat/stream")
    async def chat_stream(ws: WebSocket):
        """Delta 스트리밍 데모 라우트.
        흐름:
          1) 연결 수락 후 레이트리밋 검사(접속 시 1카운트)
          2) 첫 메시지(JSON)를 파싱 → {"type":"start","prompt":...} 요구
          3) init 응답 전송
          4) prompt를 가공한 문장을 8단어 단위로 잘라 **delta** 이벤트 연속 전송
          5) done 전송 및 사용량/지연/비용을 기록
        예외 처리:
          - JSON 파싱 실패/프로토콜 위반 → error 후 코드 1003으로 종료
          - 레이트리밋 초과 → error 후 코드 4408(policy violation)
          - 기타 예외 → error 후 코드 1011(서버 오류)
        """
        await ws.accept()

        # 식별자 키(우선순위: X-UID 헤더 → uid 쿼리)
        query = dict(ws.query_params)
        uid: Optional[str] = ws.headers.get("X-UID") or query.get("uid")
        ip = ws.client.host if ws.client else "unknown"

        # 1) 레이트리밋 검사(접속 이벤트 자체를 1건으로 카운트)
        try:
            await limiter.check_ws(uid, ip)
        except RateLimitExceeded as e:
            await ws.send_json({
                "type": "error",
                "error": "rate_limited",
                "reset_in_sec": e.detail["reset_in_sec"],
            })
            await ws.close(code=4408)  # policy violation
            return

        session_id = str(uuid.uuid4())
        started = time.perf_counter()

        try:
            # 2) 첫 메시지 수신: {"type":"start","prompt":"..."}
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "error": "bad_json"})
                await ws.close(1003)  # unsupported data
                return

            if msg.get("type") != "start" or "prompt" not in msg:
                await ws.send_json({"type": "error", "error": "expected_start"})
                await ws.close(1003)
                return

            prompt = str(msg["prompt"])  # 원본 프롬프트(로깅/사용량 산정용)
            tokens_in = _estimate_tokens(prompt)

            # 3) init 이벤트 전송(계약 동기화)
            await ws.send_json({"type": "init", "id": session_id, "model": "gpt-5-nano"})

            # 4) 응답 합성(데모): 에코+도우미 문장을 8단어 단위로 delta 전송
            synthetic = f"I received: {prompt} — Let's practice concise English. "
            words = synthetic.split(" ")
            chunks = [" ".join(words[i:i + 8]) for i in range(0, len(words), 8)]

            tokens_out = 0
            for i, ch in enumerate(chunks):
                # UX를 위한 속도 제어: 80ms 간격으로 토막 응답 전송
                await asyncio.sleep(0.08)
                tokens_out += _estimate_tokens(ch)

                # 연결이 여전히 살아있는지 확인
                if ws.application_state != WebSocketState.CONNECTED:
                    break

                await ws.send_json({"type": "delta", "index": i, "text": ch})

            # 스트림 종료 알림
            await ws.send_json({"type": "done"})

            # 5) 지표 산출 및 사용량 기록(에러가 나더라도 사용자 흐름엔 영향 X)
            latency_ms = int((time.perf_counter() - started) * 1000)
            # 러프 단가 가정: $0.003/1K(in), $0.006/1K(out)
            cost = round(tokens_in * 0.003 / 1000 + tokens_out * 0.006 / 1000, 6)

            try:
                async with get_session() as s:
                    await record_usage(
                        s,
                        route="ws:/chat/stream",
                        uid=uid,
                        ip=ip,
                        tokens_in=tokens_in,
                        tokens_out=tokens_out,
                        cost_usd=cost,
                        latency_ms=latency_ms,
                        extra={"session_id": session_id},
                    )
            except Exception:
                # 기록 실패는 사용성에 영향 주지 않도록 무시
                pass

        except WebSocketDisconnect:
            # 클라이언트가 정상적으로 연결 종료한 경우
            return
        except Exception:
            # 알 수 없는 오류 → error 후 서버 오류 코드로 종료
            try:
                await ws.send_json({"type": "error", "error": "internal_error"})
            finally:
                await ws.close(code=1011)
