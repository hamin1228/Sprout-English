# -----------------------------------------------------------------------------
# 메트릭/대시보드 모듈 개요 (server/app/metrics.py)
# -----------------------------------------------------------------------------
# 이 모듈은 FastAPI 서버의 요청 성능과 안정성을 관찰하기 위한
# "인메모리 메트릭 수집기"를 제공합니다.
#
# 주요 역할:
#   - 각 HTTP 요청에 대해 지연 시간(ms)과 상태 코드(성공/에러)를 기록
#   - 최근 window_sec(기본 300초, 5분) 동안의 데이터만 유지해 메모리 사용 제한
#   - 엔드포인트별 P95 지연 시간(p95_ms), 에러율(error_rate), 요청 수(count)를 계산
#   - 미리 정의한 SLO(SLO_LATENCY_P95_MS, SLO_ERROR_RATE_MAX)를 기준으로
#     위반 여부를 평가하여 알람 리스트를 생성
#
# 사용 흐름(보고서용 요약):
#   1) main.py의 HTTP 미들웨어에서 각 요청 완료 시 record_request(...)를 호출
#      - key: "GET /healthz" / "POST /speech/turn" 와 같은 엔드포인트 식별자
#      - status_code: 응답 코드(200, 500 등)
#      - duration_ms: 처리 시간(밀리초 단위)
#   2) /metrics/json 엔드포인트에서 snapshot() 결과를 조회해
#      - P95 지연 시간, 에러율, 요청 수를 JSON 형태로 표시
#   3) /metrics/alerts 엔드포인트에서 evaluate_slo() 결과를 조회해
#      - SLO를 초과한 엔드포인트만 필터링하여 "ALERT" 리스트로 제공
#
# 설계 의도:
#   - 외부 모니터링 스택(Prometheus, Grafana 등)을 도입하지 않고도
#     캡스톤 과제 범위에서 P95/에러율/SLO를 설명할 수 있도록 최소 구현
#   - 인메모리로만 동작하므로 재시작 시 메트릭은 리셋되지만,
#     구현 복잡도와 운영 부담을 줄이는 대신 "개발/실험용 대시보드"에 초점을 맞춤
# -----------------------------------------------------------------------------
# server/app/metrics.py
from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque
from dataclasses import dataclass, asdict
from typing import Deque, Dict, List, Tuple, Any


# SLO / Alert 기준 (필요시 조정)
# - SLO_LATENCY_P95_MS:
#     최근 window_sec 동안의 P95 지연 시간이 이 값(밀리초)을 초과하면 "지연 시간 SLO 위반"으로 간주합니다.
#   예) 2000.0이면, 전체 요청의 95%가 2초 이내에 응답해야 한다는 의미입니다.
# - SLO_ERROR_RATE_MAX:
#     동일 윈도우에서 에러율(상태 코드 500 이상 비율)이 이 값을 초과하면 "에러율 SLO 위반"으로 간주합니다.
#   예) 0.05이면, 에러율이 5% 이하여야 SLO 만족으로 판단합니다.
SLO_LATENCY_P95_MS = 2000.0   # P95 지연 시간 기준(ms)
SLO_ERROR_RATE_MAX = 0.05     # 허용 가능한 최대 에러율(0.05 = 5%)


# 단일 HTTP 요청에 대한 관측값(샘플)을 나타내는 데이터 구조.
# - ms: 해당 요청의 처리 시간(밀리초)
# - ts: 샘플이 기록된 시각(UNIX timestamp, time.time() 기준)
# - status_code: HTTP 응답 코드(200, 500 등)
# RequestMetricsStore 내부의 덱(deque)에 여러 개가 쌓인 뒤,
# P95 계산 및 에러율 산출에 사용됩니다.
@dataclass
class LatencySample:
    ms: float
    ts: float
    status_code: int


# 인메모리 메트릭 저장/집계 객체.
# - FastAPI의 HTTP 미들웨어에서 호출되며, 엔드포인트별로 LatencySample 들을 누적합니다.
# - 주기적으로 snapshot() / evaluate_slo()를 호출하여
#   * endpoints["GET /healthz"].p95_ms
#   * endpoints["POST /speech/turn"].error_rate
#   와 같은 형태로 대시보드/알람에 활용할 수 있는 요약 정보를 제공합니다.
# - window_sec, max_samples를 조정함으로써
#   메모리 사용량과 "최근 몇 분 동안의 성능"을 볼지 제어할 수 있습니다.
class RequestMetricsStore:
    """
    최근 window_sec 동안의 요청을 최대 max_samples 개까지 유지하면서
    P95, 에러율 등을 계산하는 간단한 인메모리 메트릭 스토어.
    """
    def __init__(self, window_sec: int = 300, max_samples: int = 1000) -> None:
        self.window_sec = window_sec
        self.max_samples = max_samples
        self._lock = asyncio.Lock()
        self._data: Dict[str, Deque[LatencySample]] = defaultdict(deque)

    async def record_request(
        self,
        key: str,
        status_code: int,
        duration_ms: float,
    ) -> None:
        now = time.time()
        sample = LatencySample(ms=duration_ms, ts=now, status_code=status_code)

        async with self._lock:
            dq = self._data[key]
            dq.append(sample)
            if len(dq) > self.max_samples:
                dq.popleft()
            self._prune_old_locked(now)

    def _prune_old_locked(self, now: float) -> None:
        cutoff = now - self.window_sec
        for key, dq in list(self._data.items()):
            while dq and dq[0].ts < cutoff:
                dq.popleft()

    async def snapshot(self) -> Dict[str, Dict[str, Any]]:
        """
        각 key(METHOD PATH)별로 count, p95_ms, error_rate 를 계산해서 반환.
        """
        now = time.time()
        async with self._lock:
            self._prune_old_locked(now)
            copied: Dict[str, List[LatencySample]] = {
                key: list(dq) for key, dq in self._data.items()
            }

        summary: Dict[str, Dict[str, Any]] = {}
        for key, samples in copied.items():
            if not samples:
                continue

            # P95 계산 방법:
            # - 해당 엔드포인트에 대한 모든 지연 시간을 오름차순 정렬
            # - 전체 개수 n에 대해, 인덱스 int(n * 0.95) - 1 위치의 값을 P95로 사용
            #   (예: 100개의 샘플이 있으면, 95번째(0-based 인덱스 94) 값이 P95)
            latencies = sorted(s.ms for s in samples)
            n = len(latencies)
            p95_index = max(0, int(n * 0.95) - 1)
            p95_ms = latencies[p95_index]

            total = n
            errors = sum(1 for s in samples if s.status_code >= 500)
            error_rate = errors / total if total > 0 else 0.0

            summary[key] = {
                "count": total,
                "p95_ms": p95_ms,
                "error_rate": error_rate,
                "errors": errors,
            }

        return summary

    async def evaluate_slo(self) -> List[Dict[str, Any]]:
        """
        SLO 기준을 넘는 항목만 반환.
        """
        snap = await self.snapshot()
        alerts: List[Dict[str, Any]] = []

        for key, m in snap.items():
            p95_ms = m["p95_ms"]
            err = m["error_rate"]

            # SLO 위반 판정:
            # - P95 지연 시간이 기준값(SLO_LATENCY_P95_MS)을 초과하거나,
            # - 에러율이 기준값(SLO_ERROR_RATE_MAX)을 초과하는 경우
            #   해당 엔드포인트를 "알람 대상"으로 간주하여 alerts 리스트에 추가합니다.
            if p95_ms > SLO_LATENCY_P95_MS or err > SLO_ERROR_RATE_MAX:
                alerts.append(
                    {
                        "key": key,
                        "p95_ms": p95_ms,
                        "error_rate": err,
                        "count": m["count"],
                        "violations": {
                            "latency_p95": p95_ms > SLO_LATENCY_P95_MS,
                            "error_rate": err > SLO_ERROR_RATE_MAX,
                        },
                        "slo": {
                            "latency_p95_ms": SLO_LATENCY_P95_MS,
                            "error_rate_max": SLO_ERROR_RATE_MAX,
                        },
                    }
                )

        return alerts


# 전역 인스턴스 (main.py에서 import해서 사용)
# - main.py에서는 `from app.metrics import metrics_store`로 가져와
#   HTTP 미들웨어에서 metrics_store.record_request(...)를 호출합니다.
# - /metrics/json, /metrics/alerts, /metrics/dashboard 엔드포인트는
#   이 전역 인스턴스의 snapshot()/evaluate_slo() 결과를 기반으로
#   P95/에러율/요청 수/알람 정보를 화면에 노출합니다.
metrics_store = RequestMetricsStore()