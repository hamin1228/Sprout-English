
# 초보도 이해하기 쉬운 FastAPI 서버 엔트리포인트
#
# 이 파일은 FastAPI 애플리케이션의 시작점입니다. 아래 기능을 제공합니다:
# - WAV 파일 STT(`/speech/turn`): 업로드된 WAV를 검증/저장 후 Whisper로 전사
# - WebSocket 스트리밍 데모(`/chat/stream`): 델타 텍스트 스트림 예제
# - TOEIC Part 5 생성/채점 API(`/toeic/generate`, `/toeic/grade`)
# - 헬스체크(`/healthz`), 루트(`/`)
#
# 안전장치
# - 파일 크기/길이 검사, 확장자/MIME 검증으로 업로드 안전성 확보
# - trace_id 미들웨어로 요청-로그 상관관계 추적, 응답 헤더 전파
# - 슬라이딩 윈도우 레이트리미팅으로 남용 방지
# - 정적 파일 서빙(`/static`) 및 CORS 허용

from __future__ import annotations

import os
import io
import uuid
import logging
import asyncio
import base64
import math
import random
import struct
from datetime import datetime, timezone
from pathlib import Path
# [NEW] Any 추가: 메트릭 엔드포인트에서 Dict[str, Any] 타입 힌트 사용을 위한 확장
from typing import List, Dict, Tuple, Optional, Any
from fastapi import FastAPI, UploadFile, File, HTTPException, status, Request, Response, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.db import init_db
from app.db import get_session
# [NEW] 메트릭/레이트리밋: 대시보드·SLO 체크 및 /speech/turn 보호용 유틸리티 import
from app.metrics import metrics_store
from app.rate_limit import speech_turn_rate_limiter


from app.config_loader import settings
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, delete
 # [NEW] 임베딩 & 벡터스토어 + SRS 관련 import
 # - 임베더(build_embedder), 디스크 기반 VectorStore, SRS 헬퍼(ensure_initial_state/apply_review)
 # - Mistake/SRSState ORM, Mistake용 Pydantic 스키마, 인덱스 API 스키마 로드
from app.services.embeddings import build_embedder
from app.vectorstore import VectorStore, VSItem
from app.services.srs import ensure_initial_state, apply_review
from app.services.vocab_srs import ensure_vocab_state, apply_vocab_review
from app.models import Mistake, SRSState, VocabCard, VocabSRSState
from app.schemas import (
    MistakeCreate,
    MistakeOut,
    ReviewIn,
    SRSItem,
    UpsertReq,
    QueryReq,
    VocabCardCreate,
    VocabCardUpdate,
    VocabCardOut,
    VocabImportRequest,
    VocabImportResult,
    VocabSRSItem,
    VocabReviewIn,
    VocabReviewOut,
    VocabMCQItem,
    VocabLevel,
)
import re
from openai import OpenAI
_client = None  # OpenAI 클라이언트 싱글턴
_stt_pipeline = None  # STTPipeline 싱글턴
import json, time
from typing import AsyncGenerator
from fastapi import WebSocket, WebSocketDisconnect, Body
from fastapi import Query
# [NEW] HTMLResponse 추가: /metrics/dashboard HTML 대시보드 응답용
from fastapi.responses import StreamingResponse, HTMLResponse
from collections import deque
from app.routers import writing
from app.schemas import GenerateRequest, GenerateResponse, GradeRequest, GradeResponse
from app.toeic import generate_toeic_set, grade_toeic_set
from .tts import router as tts_router
from app.stt_pipeline import STTPipeline
from app.realtime_speech import register_realtime_speech_routes

# FastAPI 서버 엔트리포인트(음성 STT 포함)
#
# 개요
# 1) .env 자동 로드(server/.env) → OPENAI_API_KEY 등 환경변수 사용
# 2) 정적 서빙: /static → settings.STORAGE_LOCAL_PATH (기본 ./app/storage)
# 3) 요청 추적: trace_id 미들웨어 + 응답 헤더 X-Trace-Id
# 4) 파일 검증: 크기(≤10MB), 길이(≤60s, WAV 헤더 파싱)
# 5) STT: OpenAI Whisper API 사용(실패 시 개발용 스텁)
# 6) CORS 허용(*) 및 선택 라우터 포함
#
# ENV 예시(.env)
# - OPENAI_API_KEY=sk-...        # 필수: OpenAI API 키
# - (선택) 모델/타임아웃/저장경로는 코드 기본값 사용
#
# 실행 예시
#   cd server
#   uv run uvicorn app.main:app --reload --port 8000
#
# 테스트 예시(curl)
#   curl -s -F "file=@/path/to/rec.wav;type=audio/wav" "http://localhost:8000/speech/turn?language=ko" | jq

app = FastAPI(title=getattr(settings, 'APP_NAME', 'english_ai'), version=getattr(settings, 'VERSION', '0.1.0'))
app.include_router(tts_router)
register_realtime_speech_routes(app)


# ===== 기본 설정(초보용 설명) =====
# - MAX_AUDIO_BYTES: 업로드 가능한 오디오 최대 크기(바이트)
# - MAX_DURATION_S: 허용 길이(초)
# - ALLOWED_WAV_MIME_TYPES: 지원하는 WAV MIME 타입 목록
# - DEFAULT_*: OpenAI/저장 경로 등 기본값
MAX_AUDIO_BYTES = 10 * 1024 * 1024

MAX_DURATION_S = 60

ALLOWED_WAV_MIME_TYPES = {'audio/wav', 'audio/x-wav', 'audio/wave', 'audio/m4a', 'audio/mp4', 'audio/x-m4a', 'audio/mpeg', 'application/octet-stream'}

DEFAULT_WHISPER_MODEL = ''

DEFAULT_OPENAI_TIMEOUT_S = 60

DEFAULT_STORAGE_LOCAL_PATH = './app/storage'

DEFAULT_TTS_MODEL = 'gpt-4o-mini-tts'

DEFAULT_TTS_VOICE = 'nova'
DEFAULT_TTS_SPEED = '1.0'


_cors = getattr(settings, 'CORS_ORIGINS', ['*'])

_static_dir = getattr(settings, 'STORAGE_LOCAL_PATH', DEFAULT_STORAGE_LOCAL_PATH)

_FILENAME_SAFE = re.compile('[^A-Za-z0-9._-]')


# 로깅 어댑터
# - log.info(..., trace_id=...) 형태로 호출하면 trace_id를 안전하게 extra에 주입합니다.
# - 미들웨어가 생성한 request.state.trace_id 와 함께 사용해 요청-로그를 연결합니다.
class TraceLoggerAdapter(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        trace_id = kwargs.pop('trace_id', None) or '-'
        kwargs.setdefault('extra', {})
        kwargs['extra']['trace_id'] = trace_id
        return (msg, kwargs)

logger = logging.getLogger('app.speech')
log = TraceLoggerAdapter(logger, {})
import inspect

async def _maybe_await(x):
    """Await value if it's awaitable; otherwise return it directly."""
    return await x if inspect.isawaitable(x) else x
 
 # ===== 레이트 리미팅(슬라이딩 윈도우) =====
# 초당/분당 호출 횟수를 제한해 서버를 보호합니다.
class _SlidingWindow:
    def __init__(self, limit: int, window_sec: int=60):
        self.limit = limit
        self.window_sec = window_sec
        self.events = deque()

    def check_and_add(self) -> float:
        """허용되면 0.0, 초과면 '남은 대기 초(second)'를 반환."""
        now = time.monotonic()
        w = self.window_sec
        while self.events and now - self.events[0] > w:
            self.events.popleft()
        if len(self.events) >= self.limit:
            return w - (now - self.events[0])
        self.events.append(now)
        return 0.0


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
    ip_norm = (ip or "").strip().lower()
    return ip_norm in {"127.0.0.1", "::1", "localhost"}


# 레이트 리미터 관리자
# - uid/IP 단위로 슬라이딩 윈도우 버킷을 관리합니다.
# - uid가 있으면 uid 버킷 사용, 없으면 ip 버킷 사용.
# - check() → 0.0이면 허용, >0이면 재시도까지 남은 대기 초(second).
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
        self._uid = {}
        self._ip = {}

    def check(self, uid: Optional[str], ip: str) -> float:
        """허용 시 0.0, 초과 시 재시도까지 남은 초(second)."""
        if self.skip_local_ip and _is_local_loopback_ip(ip):
            return 0.0
        bucket = None
        if uid:
            bucket = self._uid.setdefault(uid, _SlidingWindow(self.uid_limit, self.window_sec))
        else:
            bucket = self._ip.setdefault(ip, _SlidingWindow(self.ip_limit, self.window_sec))
        return bucket.check_and_add()

_limiter = _Limiter(
    uid_limit=_env_int("CHAT_WS_UID_LIMIT", 60),
    ip_limit=_env_int("CHAT_WS_IP_LIMIT", 6),
    window_sec=_env_int("CHAT_WS_WINDOW_SEC", 60),
    skip_local_ip=_env_bool("CHAT_WS_SKIP_LOCAL_IP", False),
)
app.add_middleware(CORSMiddleware, allow_origins=_cors, allow_credentials=True, allow_methods=['*'], allow_headers=['*'])

app.include_router(writing.router)
app.mount("/static", StaticFiles(directory=_static_dir, html=False), name="static")


# HTTP 미들웨어: 요청마다 trace_id(UUID4)를 생성하여
# - request.state.trace_id 로 보관하고
# - 응답 헤더 X-Trace-Id 로 전달합니다.
# 디버깅/서버 로그 상관관계를 위해 사용합니다.
@app.middleware("http")
async def _trace_middleware(request: Request, call_next):
    trace_id = str(uuid.uuid4())
    request.state.trace_id = trace_id
    response: Response = await call_next(request)
    response.headers['X-Trace-Id'] = trace_id
    return response

# 요청 지연 시간/에러를 수집하는 메트릭 미들웨어
# [NEW] 요청 지연시간/P95/에러율 수집용 HTTP 미들웨어 (대시보드·SLO용)
@app.middleware("http")
async def _metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    status_code = 500
    path = request.url.path
    method = request.method
    key = f"{method} {path}"

    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        duration_ms = (time.perf_counter() - start) * 1000.0
        # /metrics/* 자체는 계측에서 제외
        if not path.startswith("/metrics"):
            await metrics_store.record_request(
                key=key,
                status_code=status_code,
                duration_ms=duration_ms,
            )


# 파일명 안전화 유틸리티
# - 경로 구분자(../, \\ 등) 제거 → 디렉터리 탈출 방지
# - 허용되지 않는 문자([^A-Za-z0-9._-])는 '_'로 치환
# - 비어있으면 'audio.wav' 기본값 사용
def _safe_filename(name: str) -> str:
    name = (name or '').strip()
    if not name:
        return 'audio.wav'
    name = name.replace('\\', '/').split('/')[-1]
    return _FILENAME_SAFE.sub('_', name)

# WAV 길이(ms) 계산
# - 표준 wave 모듈로 헤더를 읽어 프레임 수/샘플레이트로 길이를 산출합니다.
# - 예외는 상위에서 HTTP 오류로 변환 처리합니다.
def _wav_duration_ms(data: bytes) -> int:
    import wave
    with wave.open(io.BytesIO(data)) as w:
        frames = w.getnframes()
        rate = w.getframerate() or 1
        return int(frames * 1000 / rate)


def _wav_signal_profile(data: bytes) -> Optional[Dict[str, float]]:
    import wave

    with wave.open(io.BytesIO(data)) as wav_file:
        sample_rate = wav_file.getframerate() or 1
        channels = wav_file.getnchannels() or 1
        sample_width = wav_file.getsampwidth()
        frame_count = wav_file.getnframes()
        if sample_width != 2 or frame_count <= 0:
            return None

        window_frames = min(frame_count, int(sample_rate * 1.5))
        raw = wav_file.readframes(window_frames)

    total_samples = len(raw) // sample_width
    if total_samples <= 0:
        return None

    unpacked = struct.unpack(f"<{total_samples}h", raw)
    mono_samples = unpacked[::channels]
    if len(mono_samples) < max(800, sample_rate // 8):
        return None

    peak = max(abs(sample) for sample in mono_samples) / 32768.0
    rms = math.sqrt(
        sum((sample / 32768.0) ** 2 for sample in mono_samples) /
        max(len(mono_samples), 1)
    )
    clipped_ratio = (
        sum(1 for sample in mono_samples if abs(sample) >= 32000) /
        max(len(mono_samples), 1)
    )
    zero_crossings = sum(
        1
        for index in range(1, len(mono_samples))
        if (mono_samples[index - 1] <= 0 < mono_samples[index]) or
        (mono_samples[index - 1] >= 0 > mono_samples[index])
    )
    duration_sec = len(mono_samples) / sample_rate
    tone_hz = zero_crossings / 2 / max(duration_sec, 0.001)
    return {
        'peak': round(peak, 4),
        'rms': round(rms, 4),
        'clipped_ratio': round(clipped_ratio, 4),
        'tone_hz': round(tone_hz, 1),
        'duration_ms': int(duration_sec * 1000),
    }


def _is_unstable_wav_signal(profile: Optional[Dict[str, float]]) -> bool:
    if not profile:
        return False
    if int(profile.get('duration_ms', 0)) < 800:
        return False

    peak = float(profile.get('peak', 0.0))
    rms = float(profile.get('rms', 0.0))
    clipped_ratio = float(profile.get('clipped_ratio', 0.0))
    tone_hz = float(profile.get('tone_hz', 0.0))

    looks_like_full_scale_tone = (
        peak >= 0.98 and
        0.68 <= rms <= 0.73 and
        160.0 <= tone_hz <= 320.0
    )
    looks_like_clipped_input = (
        peak >= 0.99 and
        rms >= 0.55 and
        clipped_ratio >= 0.015
    )
    return looks_like_full_scale_tone or looks_like_clipped_input

 # 사용 흐름
 # 1) 파일 전체 바이트를 로드 → 크기 제한 확인(≤10MB)
 # 2) MIME 또는 RIFF/WAVE 시그니처로 WAV 여부 판별
 # 3) wave 헤더 파싱으로 길이 확인(≤60초)
 # 4) 저장 경로: {STORAGE_LOCAL_PATH}/audio/{YYYYMMDD}/{trace_id}_{원본파일명}
 # 5) /static 하위에서 접근할 수 있는 URL을 구성해 응답에 포함
# ===== 파일 검증 및 저장(핵심 로직) =====
async def _validate_and_save_audio(file: UploadFile, request: Request) -> dict:
    trace_id = getattr(request.state, 'trace_id', '-')
    # 1) 파일 사이즈 확인
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail={'code': 'empty_file', 'message': '파일이 비어 있습니다.'})
    if len(raw) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail={'code': 'too_large', 'message': '파일 크기는 최대 10MB까지 허용됩니다.'})
    mime = (file.content_type or '').lower()
    # 2) MIME 타입 확인 및 길이 검증
    duration_ms = None
    signal_profile = None
    try:
        # WAV/M4A/AAC 파일 검증: content_type 체크 (관대하게 처리)
        ct = file.content_type or ''
        # 오디오 파일이면 일단 허용 (Whisper가 다양한 형식 지원)
        if not ct.startswith('audio/') and ct != 'application/octet-stream':
            log.warning(f'Unsupported MIME type rejected: {ct}', trace_id=trace_id)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={'code': 'unsupported_format', 'message': f'지원하지 않는 파일 형식입니다: {ct}'}
            )
        
        # WAV 파일만 헤더 파싱으로 길이 검증 (M4A/AAC는 건너뛰기)
        if mime in ALLOWED_WAV_MIME_TYPES or (raw[:4] == b'RIFF' and raw[8:12] == b'WAVE'):
            try:
                duration_ms = _wav_duration_ms(raw)
                signal_profile = _wav_signal_profile(raw)
                if duration_ms > MAX_DURATION_S * 1000:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail={'code': 'file_too_long', 'message': f'오디오가 너무 깁니다: {duration_ms}ms \u003e {MAX_DURATION_S}초'}
                    )
            except HTTPException:
                raise
            except Exception:
                # WAV 헤더 파싱 실패는 무시하고 계속 진행 (Whisper가 처리)
                log.warning(f'WAV header parsing failed, but continuing', trace_id=trace_id)
        else:
            # M4A/AAC 등 다른 형식은 길이 검증 건너뛰기 (Whisper가 처리)
            log.info(f'Non-WAV audio file detected ({ct}), skipping duration check', trace_id=trace_id)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail={'code': 'invalid_header', 'message': '오디오 헤더를 해석할 수 없습니다.'})
    trace_id = getattr(request.state, 'trace_id', None) or str(uuid.uuid4())
    # 3) 저장 경로 구성: {STORAGE_LOCAL_PATH}/audio/{YYYYMMDD}/{trace_id}_원본이름
    base = Path(getattr(settings, 'STORAGE_LOCAL_PATH', './app/storage'))
    day = datetime.utcnow().strftime('%Y%m%d')
    dest_dir = base / 'audio' / day
    dest_dir.mkdir(parents=True, exist_ok=True)
    safe_name = _safe_filename(file.filename)
    dest_path = dest_dir / f'{trace_id}_{safe_name}'
    dest_path.write_bytes(raw)
    audio_url = '/static/' + dest_path.relative_to(base).as_posix()
    return {'trace_id': trace_id, 'bytes': len(raw), 'duration_ms': duration_ms, 'audio_path': str(dest_path), 'audio_url': audio_url, 'mime': mime or 'application/octet-stream', 'original_filename': file.filename or 'audio.wav', 'signal_profile': signal_profile}

# ===== STT(Whisper/OpenAI) 유틸 =====
# OpenAI 클라이언트를 한 번만 생성해 재사용합니다(싱글턴).
# OpenAI 클라이언트 팩토리(싱글턴)
# - 최초 1회 생성 후 캐싱하여 연결/설정 비용을 줄입니다.
# - 타임아웃: OPENAI_TIMEOUT_S 환경변수(기본 60초)
def _get_client() -> OpenAI:
    global _client
    if _client is None:
        # SDK 버전에 따라 생성자 timeout 인자가 없을 수 있어,
        # 클라이언트 생성은 기본으로 하고 요청 호출 시 timeout을 전달합니다.
        _client = OpenAI()
    return _client

# OpenAI Whisper 전사 유틸
# - 입력: 로컬 WAV 경로, 언어 코드(선택, 미지정 시 자동감지)
# - 우선 verbose_json(segments 포함)으로 요청, 실패 시 일반 응답으로 폴백
# - 출력: (transcript 문자열, segments[{start_ms,end_ms,text}])
def _stt_openai_transcribe_file(path: str, language: str | None=None) -> Tuple[str, List[Dict]]:
    client = _get_client()
    model = os.getenv('OPENAI_WHISPER_MODEL') or DEFAULT_WHISPER_MODEL
    model = model.strip()
    if not model:
        raise RuntimeError('openai_stt_model_not_configured')
    timeout_s = float(os.getenv('OPENAI_TIMEOUT_S') or DEFAULT_OPENAI_TIMEOUT_S)
    kwargs: Dict = {'model': model}
    # Force English when no language is provided or 'auto' is specified
    lang_norm = (language or '').strip().lower()
    # [MODIFIED] 자동 감지를 위해 강제 설정 제거
    # if lang_norm in ('', 'auto'):
    #     language = 'en'
    if language and lang_norm not in ('', 'auto'):
        kwargs['language'] = language
    # [MODIFIED] 언어 환각 방지를 위한 프롬프트 제거
    # kwargs['prompt'] = "The audio is a user speaking    if language and lang_norm not in ('', 'auto'):
        kwargs['language'] = language
    
    # OpenAI transcription 모델 중 verbose_json을 지원하는 경우 세그먼트를 함께 반환
    try:
        with open(path, 'rb') as f:
            resp = client.audio.transcriptions.create(file=f, response_format='verbose_json', timeout=timeout_s, **kwargs)
        
        # 응답 파싱
        transcript = getattr(resp, 'text', '') or ''
        segments = []
        
        # 세그먼트 정보 추출
        if hasattr(resp, 'segments') and resp.segments:
            for seg in resp.segments:
                try:
                    segments.append({
                        'start_ms': int(seg.start * 1000),
                        'end_ms': int(seg.end * 1000),
                        'text': seg.text.strip()
                    })
                except Exception:
                    continue
        
        return (transcript, segments)
    except Exception as e:
        log.error(f'Whisper API failed: {type(e).__name__}: {str(e)}', trace_id='-')
        raise

# STT 폴백 스텁(개발 편의용)
# - 실제 Whisper 호출이 실패했을 때 데모 데이터를 반환합니다.
def _stub_stt(_: bytes, __: str) -> Tuple[str, List[Dict]]:
    transcript = 'demo transcript'
    segments = [{'start_ms': 0, 'end_ms': 1000, 'text': 'demo'}, {'start_ms': 1000, 'end_ms': 2000, 'text': 'transcript'}]
    return (transcript, segments)

# 간단한 문장 분리기
# - 마침표/물음표/느낌표 뒤 공백 기준으로 분리합니다.
def _split_sentences(text: str) -> List[str]:
    parts = re.split('(?<=[.!?])\\s+', text.strip())
    return [p for p in parts if p]

# 16-bit PCM 모노 사인파 생성기
# - duration_sec 길이의 톤을 생성(기본 440Hz)
# - 값 범위 보정 후 little-endian signed 16-bit로 직렬화
def _tone_pcm(duration_sec: float, sr: int=16000, freq: float=440.0, amp: float=0.7) -> bytes:
    import math
    frames = int(sr * duration_sec)
    a = max(0.0, min(1.0, amp))
    out = bytearray()
    for n in range(frames):
        x = a * math.sin(2 * math.pi * freq * n / sr)
        v = int(max(-1.0, min(1.0, x)) * 32767)
        out += v.to_bytes(2, 'little', signed=True)
    return bytes(out)

# ===== TTS 데모: 텍스트→PCM 을 NDJSON으로 스트리밍 =====
# 프런트엔드가 한 줄씩 처리하기 쉽게 JSON 라인을 보냅니다.
async def _ndjson_stream(text: str) -> AsyncGenerator[bytes, None]:
    sr = 16000
    yield (json.dumps({'type': 'init', 'content_type': 'audio/pcm', 'sample_rate': sr, 'channels': 1}) + '\n').encode('utf-8')
    for i, sent in enumerate(_split_sentences(text)):
        dur = max(0.6, min(1.2, len(sent) / 20.0))
        tone = 440.0 if i % 2 == 0 else 660.0
        pcm = _tone_pcm(dur, sr, freq=tone, amp=0.7)
        yield (json.dumps({'type': 'chunk', 'seq': i, 'sentence': sent, 'pcm_b64': base64.b64encode(pcm).decode('ascii'), 'duration_sec': round(dur, 3)}) + '\n').encode('utf-8')
        await asyncio.sleep(0.03)
    yield (json.dumps({'type': 'done'}) + '\n').encode('utf-8')

# 서버 시작 시 초기화 루틴
# - 시작 시각 기록, TTS 기본 ENV 설정, DB 스키마 초기화 시도
# - 실패 시 경고 로그만 남기고 서버는 계속 실행
async def _init_db_background() -> None:
    try:
        await asyncio.wait_for(init_db(), timeout=5.0)
        log.info('Database schema initialized successfully.', trace_id='-')
    except Exception as e:
        log.warning('Database schema initialization failed: %r', e, trace_id='-')


@app.on_event("startup")
async def startup_event():
    app.state.started_at = datetime.utcnow()
    log.info('Server starting up...', trace_id='-')
    os.environ.setdefault('OPENAI_TTS_MODEL', DEFAULT_TTS_MODEL)
    os.environ.setdefault('OPENAI_TTS_VOICE', DEFAULT_TTS_VOICE)
    os.environ.setdefault('OPENAI_TTS_SPEED', DEFAULT_TTS_SPEED)
    log.info('TTS default environment variables configured.', trace_id='-')
    # STTPipeline 초기화 (현재 비활성화 - 안정성을 위해 단순 Whisper 사용)
    # global _stt_pipeline
    # try:
    #     cfg_path = os.path.join(os.path.dirname(__file__), '..', 'config', 'stt.yaml')
    #     dict_path = os.path.join(os.path.dirname(__file__), '..', 'config', 'dictionaries', 'general.json')
    #     if os.path.exists(cfg_path):
    #         _stt_pipeline = STTPipeline(cfg_path=os.path.abspath(cfg_path), 
    #                                     dict_path=os.path.abspath(dict_path) if os.path.exists(dict_path) else None)
    #         log.info('STT Pipeline initialized successfully.', trace_id='-')
    #     else:
    #         log.warning(f'STT config not found at {cfg_path}, pipeline disabled.', trace_id='-')
    # except Exception as e:
    #     log.warning(f'STT Pipeline initialization failed: {e}, using fallback.', trace_id='-')
    asyncio.create_task(_init_db_background())

# 단일 WAV 파일을 받아 검증/저장 후 STT 수행
# 요청: multipart/form-data (file), 쿼리 language(선택)
# 응답: trace_id, 파일정보(bytes/duration_ms), transcript, segments, audio_url, provider, error(선택)
# 절차: _validate_and_save_audio → Whisper 호출(실패 시 스텁)
@app.post("/speech/turn")
async def speech_turn(request: Request, file: UploadFile = File(...), language: Optional[str] = None):
    # [NEW] /speech/turn 전용 IP 기반 레이트리밋 (과호출 방지, 429 응답)
    # 간단 IP 기반 레이트 리밋
    client_ip = request.client.host if request.client else "unknown"
    if not speech_turn_rate_limiter.allow(client_ip):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many /speech/turn requests, please slow down.",
        )

    # 1) 검증 및 저장
    info = await _validate_and_save_audio(file, request)
    audio_path = info['audio_path']
    duration_ms = int(info['duration_ms'] or 0)
    signal_profile = info.get('signal_profile')

    if _is_unstable_wav_signal(signal_profile):
        log.warning(
            'Unstable mic input detected profile=%s path=%s',
            signal_profile,
            audio_path,
            trace_id=getattr(request.state, 'trace_id', '-'),
        )
        return {
            'trace_id': getattr(request.state, 'trace_id', None),
            'filename': info['original_filename'],
            'size_bytes': info['bytes'],
            'duration_ms': duration_ms,
            'transcript': '',
            'segments': [],
            'audio_url': info['audio_url'],
            'provider': 'signal_guard',
            'error': 'mic_input_unstable',
            'signal_profile': signal_profile,
        }

    # [MODIFIED] 프롬프트 제거 (환각 원인 가능성) 및 디버그 로깅 추가
    # kwargs['prompt'] = "The audio is a user speaking in English or Korean. Please transcribe it accurately."
    
    log.info(f"STT Request: {audio_path}, Size: {info['bytes']} bytes, Duration: {duration_ms} ms", trace_id=getattr(request.state, 'trace_id', '-'))

    # 2) STT 시도: STTPipeline 사용 (실패 시 기존 Whisper로 폴백)
    provider = 'pipeline'
    transcript = ''
    segments = []
    
    # 먼저 STTPipeline 시도
    if _stt_pipeline is not None:
        try:
            with open(audio_path, 'rb') as f:
                audio_bytes = f.read()
            result = _stt_pipeline.run(audio_bytes)
            # sentences의 text를 transcript로 사용
            if result.get('sentences'):
                transcript = ' '.join(s['text'] for s in result['sentences'] if s['text'])
            # segments 정보 추출
            segments = result.get('segments', [])
            log.info(f"STTPipeline success: {len(segments)} segments", trace_id=getattr(request.state, 'trace_id', '-'))
        except Exception as e:
            log.warning(f'STTPipeline failed: {e}, falling back to direct Whisper', trace_id=getattr(request.state, 'trace_id', '-'))
            provider = 'openai'
            try:
                transcript, segments = _stt_openai_transcribe_file(audio_path, language)
            except Exception as e2:
                log.warning('STT failed; using stub: %r', e2, trace_id=getattr(request.state, 'trace_id', '-'))
                transcript, segments = _stub_stt(b'', language or '')
                provider = 'stub'
    else:
        # STTPipeline이 없으면 기존 방식 사용
        provider = 'openai'
        trace_id = getattr(request.state, 'trace_id', '-') # Ensure trace_id is available
        log.info(f"Calling Whisper API for {audio_path}", trace_id=trace_id)
        try:
            log.info('Calling Whisper API...', trace_id=trace_id)
            transcript, segments = _stt_openai_transcribe_file(audio_path, language)
            log.info(f'Whisper result: {transcript}', trace_id=trace_id)
            
            # 잘못된 전사 필터링 (BELL, 무음 표시 등)
            invalid_transcripts = ['BELL', '[BLANK_AUDIO]', '(bell ringing)', '(silence)', '[Music]', '[음악]']
            transcript_clean = transcript.strip()
            
            if transcript_clean.upper() in [x.upper() for x in invalid_transcripts] or len(transcript_clean) < 2:
                log.warning(f'Invalid transcript detected and filtered: "{transcript}"', trace_id=trace_id)
                transcript = ''  # 빈 문자열로 대체
                segments = []
            log.info(f"Whisper success: transcript length={len(transcript)}, segments={len(segments)}", trace_id=trace_id)
        except Exception as e:
            log.error(f'Whisper API failed: {type(e).__name__}: {str(e)}', trace_id=trace_id)
            transcript, segments = _stub_stt(b'', language or '')
            provider = 'stub'
    # 3) 응답
    return {
        'trace_id': getattr(request.state, 'trace_id', None),
        'filename': info['original_filename'],
        'size_bytes': info['bytes'],
        'duration_ms': duration_ms,
        'transcript': transcript,
        'segments': segments,
        'audio_url': info['audio_url'],
        'provider': provider,
    }

# 루트 핸들러: 앱 이름/버전 반환
@app.get("/")
async def root():
    return {'app': getattr(settings, 'APP_NAME', 'english_ai'), 'version': getattr(settings, 'VERSION', '0.1.0')}

# 헬스체크 핸들러: 단순 OK와 UTC 타임스탬프 반환

# 메트릭 조회용 JSON 엔드포인트
# [NEW] 메트릭/SLO 대시보드 엔드포인트 세트 (/metrics/json, /metrics/alerts, /metrics/dashboard)
@app.get("/metrics/json")
async def metrics_json() -> Dict[str, Any]:
    """최근 window_sec 기준 엔드포인트별 메트릭 스냅샷."""
    snap = await metrics_store.snapshot()
    return {
        "window_sec": metrics_store.window_sec,
        "endpoints": snap,
    }


# SLO 위반 엔드포인트
@app.get("/metrics/alerts")
async def metrics_alerts() -> Dict[str, Any]:
    """SLO 기준을 넘는 엔드포인트만 알람으로 반환."""
    alerts = await metrics_store.evaluate_slo()
    return {
        "alert_count": len(alerts),
        "alerts": alerts,
    }


# 초간단 HTML 대시보드
@app.get("/metrics/dashboard", response_class=HTMLResponse)
async def metrics_dashboard() -> HTMLResponse:
    snap = await metrics_store.snapshot()

    rows_html = ""
    for key, m in snap.items():
        p95_ms = m["p95_ms"]
        error_rate = m["error_rate"] * 100.0
        count = m["count"]
        errors = m["errors"]

        row = f"""        <tr>
          <td>{key}</td>
          <td>{count}</td>
          <td>{errors}</td>
          <td>{p95_ms:.1f} ms</td>
          <td>{error_rate:.2f}%</td>
        </tr>
        """
        rows_html += row

    html = f"""    <html>
      <head>
        <title>english_ai Metrics Dashboard</title>
        <meta http-equiv="refresh" content="5" />
        <style>
          body {{
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            margin: 20px;
          }}
          table {{
            border-collapse: collapse;
            width: 100%;
          }}
          th, td {{
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
          }}
          th {{
            background-color: #f2f2f2;
          }}
          tr:nth-child(even){{background-color: #fafafa;}}
        </style>
      </head>
      <body>
        <h1>english_ai Metrics Dashboard</h1>
        <p>Window: {metrics_store.window_sec} sec (최근 윈도우 기준)</p>
        <table>
          <thead>
            <tr>
              <th>Endpoint</th>
              <th>Count</th>
              <th>Errors</th>
              <th>P95 Latency</th>
              <th>Error Rate</th>
            </tr>
          </thead>
          <tbody>
            {rows_html}
          </tbody>
        </table>
      </body>
    </html>
    """
    return HTMLResponse(content=html)


@app.get("/healthz")
def healthz():
    return {'ok': True, 'time': datetime.utcnow().isoformat() + 'Z'}

# WebSocket 델타 스트리밍 데모
# - 간단한 레이트리밋 적용(X-UID 또는 IP 기준)
# - 'start' 메시지 수신 후 델타 텍스트를 순차 전송
# [NEW] AsyncOpenAI 사용을 위한 import 추가 (상단에 추가 필요하지만, 여기서는 로컬 import로 처리하거나 기존 import 수정)
from openai import AsyncOpenAI

_async_client = None

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
    "0",
    "false",
    "no",
    "off",
}
_CHAT_STREAM_FRAGMENT_CHARS = max(1, int(os.getenv("CHAT_STREAM_FRAGMENT_CHARS", "12")))
_CHAT_STREAM_FRAGMENT_MIN_LEN = max(
    _CHAT_STREAM_FRAGMENT_CHARS + 1,
    int(os.getenv("CHAT_STREAM_FRAGMENT_MIN_LEN", "18")),
)
_CHAT_STREAM_FRAGMENT_DELAY_MS = max(0, int(os.getenv("CHAT_STREAM_FRAGMENT_DELAY_MS", "0")))

def _get_async_client() -> AsyncOpenAI:
    global _async_client
    if _async_client is None:
        _async_client = AsyncOpenAI()
    return _async_client


def _split_chat_stream_delta(text: str) -> List[str]:
    if not text:
        return []
    if len(text) < _CHAT_STREAM_FRAGMENT_MIN_LEN:
        return [text]
    return [text[i : i + _CHAT_STREAM_FRAGMENT_CHARS] for i in range(0, len(text), _CHAT_STREAM_FRAGMENT_CHARS)]


async def _translate_free_talk_reply(client: AsyncOpenAI, text: str) -> str:
    source = text.strip()
    if not source:
        return ""
    try:
        response = await client.chat.completions.create(
            model=os.getenv("OPENAI_TRANSLATE_MODEL", "gpt-5-nano"),
            messages=[
                {"role": "system", "content": _FREE_TALK_TRANSLATE_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": (
                        "Translate only the text inside <source> tags.\n"
                        f"<source>{source}</source>"
                    ),
                },
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
        log.error(f"Translate API error: {e}", trace_id='-')
        return ""

# WebSocket 델타 스트리밍 데모
# - 간단한 레이트리밋 적용(X-UID 또는 IP 기준)
# - 'start' 메시지 수신 후 델타 텍스트를 순차 전송
@app.websocket("/chat/stream")
async def chat_stream(ws: WebSocket):
    await ws.accept()
    uid: Optional[str] = ws.headers.get('X-UID') or ws.query_params.get('uid')
    ip = ws.client.host if ws.client else 'unknown'
    reset = _limiter.check(uid, ip)
    if reset > 0:
        await ws.send_json({'type': 'error', 'error': 'rate_limited', 'reset_in_sec': round(reset, 3)})
        await ws.close(code=4408)
        return
    
    session_id = str(uuid.uuid4())
    # 연결 초기화 메시지는 한 번만 보냄 (또는 매 턴마다 보낼 수도 있지만, 보통 접속 시 1회)
    await ws.send_json({'type': 'init', 'id': session_id, 'model': FREE_TALK_CHAT_MODEL})

    try:
        while True:
            # 메시지 대기 (연결이 끊기면 여기서 예외 발생)
            raw = await ws.receive_text()
            
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_json({'type': 'error', 'error': 'bad_json'})
                continue # 연결 유지하며 다음 메시지 대기

            if msg.get('type') != 'start' or 'prompt' not in msg:
                await ws.send_json({'type': 'error', 'error': 'expected_start'})
                continue

            prompt = str(msg['prompt'])
            trace_id = str(msg.get('trace_id') or session_id)
            history = msg.get('history') if isinstance(msg.get('history'), list) else []
            first_token_sent = False
            llm_started_at = time.perf_counter()

            messages = []
            messages.append({'role': 'system', 'content': _FREE_TALK_CHAT_SYSTEM_PROMPT})
            for item in history[-12:]:
                if not isinstance(item, dict):
                    continue
                role = str(item.get('role') or '').strip()
                content = str(item.get('content') or '').strip()
                if role not in {'user', 'assistant'} or not content:
                    continue
                messages.append({'role': role, 'content': content})
            if not messages or messages[-1].get('role') != 'user' or messages[-1].get('content') != prompt:
                messages.append({"role": "user", "content": prompt})
            
            # 비동기 클라이언트 사용
            client = _get_async_client()
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
                                log.info(
                                    "chat_stream llm_first_token_ms=%s trace_id=%s",
                                    first_token_ms,
                                    trace_id,
                                )
                            assistant_chunks.append(fragment)
                            await ws.send_json({'type': 'delta', 'text': fragment})
                            if (
                                _CHAT_STREAM_FRAGMENT_DELAY_MS > 0
                                and len(fragments) > 1
                                and i < len(fragments) - 1
                            ):
                                await asyncio.sleep(_CHAT_STREAM_FRAGMENT_DELAY_MS / 1000.0)

                # Send done immediately so client can flush trailing TTS quickly.
                await ws.send_json({'type': 'done'})
                if FREE_TALK_TRANSLATE_ENABLED:
                    translation = await _translate_free_talk_reply(
                        client,
                        "".join(assistant_chunks),
                    )
                    if translation:
                        await ws.send_json({'type': 'translation', 'translation': translation})
            
            except Exception as e:
                log.error(f"OpenAI API error: {e}", trace_id=trace_id)
                await ws.send_json({'type': 'error', 'error': 'llm_error'})
                # 에러가 나도 연결은 유지할 수 있음

    except WebSocketDisconnect:
        return
    except Exception as e:
        log.error(f"WebSocket error: {e}", trace_id='-')
        try:
            await ws.send_json({'type': 'error', 'error': 'internal_error'})
        finally:
            await ws.close(code=1011)


@app.post("/chat/translate")
async def chat_translate(payload: dict = Body(...)):
    text = str(payload.get("text", "")).strip()
    if not text:
        raise HTTPException(status_code=422, detail="text is required")

    client = _get_async_client()
    translation = await _translate_free_talk_reply(client, text)
    if not translation:
        raise HTTPException(status_code=502, detail="translation_error")
    return {"translation": translation}


# TOEIC Part 5 생성 API
# - LLM 없이 템플릿+distractor로 생성
# - seed 지정 시 동일 입력 → 동일 결과(중복 방지 로직 포함)
@app.post("/toeic/generate", response_model=GenerateResponse)
async def toeic_generate(req: GenerateRequest):
    return generate_toeic_set(req)

# TOEIC Part 5 채점 API
# - 클라이언트가 questions(원본)과 responses(사용자답)를 함께 전송
# - 서버 저장 없이 재현 가능, 공정성: 대소문자/공백 무시, 유효 보기는 A-D
@app.post("/toeic/grade", response_model=GradeResponse)
async def toeic_grade(req: GradeRequest):
    return grade_toeic_set(req)

# ===== Speaking Score (rule-based + optional LLM) =====
# (신규) 음성 채점 API 상세 설명
# - 작성 배경: Flutter 스피킹 탭에서 전사 텍스트·발화 길이·침묵 시간만으로 즉시 피드백을 받아야 해,
#   서버 측에서 규칙 기반 점수와 선택적 LLM 점수를 합성해 단일 JSON으로 돌려주는 엔드포인트가 필요했습니다.
# - 입력(JSON): transcript(필수), duration_ms, silence_ms_total, filler_words_override(선택) 등
# - 처리 순서:
#     1) 단어 수/말 속도(WPM)·침묵 비율·필러 빈도를 계산
#     2) Heuristic 가중치(0.4/0.3/0.3)로 rule_score 산출
#     3) 내부 gpt_client가 있을 경우 동일 지표를 전달해 보충 점수+피드백을 요청
#     4) rule_score와 llm_score(존재 시)를 6:4로 혼합하여 final_score 생성
# - 출력(JSON): transcript, 규칙 기반 세부 지표(rule_subscores), llm_score/feedback, final_score
# - 저장은 생략하고, 호출 측이 필요 시 별도 저장 API를 부르는 구조로 설계했습니다.
@app.post("/speaking/score")
async def speaking_score(
    payload: dict = Body(..., description="JSON with transcript/duration etc."),
    save: bool = Query(False, description="Set true to save (not implemented here)"),
):
    """
    Minimal /speaking/score route:
    - Computes rule-based metrics from transcript/duration and optional silence/filler override.
    - Tries to call app.services.gpt_client.get_llm_score_and_feedback if available.
    - Returns JSON; DB save is intentionally omitted in this minimal patch.
    """
    def count_words(text: str) -> int:
        return len(re.findall(r"[A-Za-z']+", text))

    DEFAULT_FILLERS = [
        "um","uh","er","erm","hmm","you know","like","so","actually",
        "basically","right","i mean","well"
    ]

    def count_fillers(text: str, fillers: List[str]) -> int:
        t = " " + re.sub(r"\s+", " ", text.lower()) + " "
        c = 0
        for f in fillers:
            pattern = r"\b" + re.escape(f) + r"\b"
            c += len(re.findall(pattern, t))
        return c

    def score_wpm(wpm: float) -> float:
        if wpm <= 60 or wpm >= 220:
            return 0.0
        if wpm <= 140:
            return (wpm - 60) / (140 - 60) * 100
        return (220 - wpm) / (220 - 140) * 100

    def score_silence_ratio(ratio: float) -> float:
        if ratio <= 0.10:
            return 100.0
        if ratio >= 0.40:
            return 0.0
        return (0.40 - ratio) / (0.40 - 0.10) * 100

    def score_filler_density(per_100w: float) -> float:
        if per_100w <= 2.0:
            return 100.0
        if per_100w >= 10.0:
            return 0.0
        return (10.0 - per_100w) / (10.0 - 2.0) * 100

    def rule_based(words: int, duration_ms: int, silence_ms_total: int, filler_count: int):
        duration_ms = max(1, int(duration_ms))
        minutes = duration_ms / 1000 / 60
        wpm = words / minutes if minutes > 0 else 0.0
        silence_ratio = (silence_ms_total / duration_ms) if duration_ms > 0 else 0.0
        filler_density = (filler_count / max(1, words)) * 100.0

        sw = score_wpm(wpm)
        ss = score_silence_ratio(silence_ratio)
        sf = score_filler_density(filler_density)
        rule = 0.4 * sw + 0.3 * ss + 0.3 * sf

        return {
            "words": words,
            "wpm": round(wpm, 2),
            "silence_ms_total": int(silence_ms_total),
            "silence_ratio": round(silence_ratio, 4),
            "filler_count": int(filler_count),
            "filler_density": round(filler_density, 2),
            "subscores": {"wpm": round(sw, 2), "silence": round(ss, 2), "filler": round(sf, 2)},
            "rule_score": round(rule, 2),
        }

    # ---- input parsing
    transcript = str(payload.get("transcript", "")).strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="transcript is required")

    duration_ms = int(payload.get("duration_ms", 0))
    silence_ms_total = int(payload.get("silence_ms_total", 0))
    filler_override = payload.get("filler_words_override") or []

    words = count_words(transcript)
    fillers = [w.lower().strip() for w in (filler_override if isinstance(filler_override, list) else [])] or DEFAULT_FILLERS
    filler_count = count_fillers(transcript, fillers)

    metrics = rule_based(words, duration_ms, silence_ms_total, filler_count)

    # ---- optional LLM
    llm_score = None
    feedback = None
    try:
        from app.services.gpt_client import get_llm_score_and_feedback  # type: ignore
        if callable(get_llm_score_and_feedback):
            llm_score, feedback = get_llm_score_and_feedback(metrics, transcript)
    except Exception:
        pass

    final_score = round(0.6 * metrics["rule_score"] + 0.4 * float(llm_score), 2) if llm_score is not None else metrics["rule_score"]

    # id 저장/DB는 이 최소 패치에선 생략
    return {
        "id": None,
        "transcript": transcript,
        **{k: v for k, v in metrics.items() if k != "subscores"},
        "rule_subscores": metrics["subscores"],
        "llm_score": llm_score,
        "final_score": final_score,
        "feedback": feedback,
    }

_FREE_TALK_SCORE_TABLE: Dict[str, List[int]] = {
    "task_fulfillment_interaction": [0, 9, 15, 21, 26, 30],
    "pronunciation_delivery": [0, 6, 10, 14, 17, 20],
    "fluency": [0, 6, 10, 14, 17, 20],
    "grammar_control": [0, 5, 8, 11, 13, 15],
    "vocabulary_expression": [0, 5, 8, 11, 13, 15],
}

_FREE_TALK_DIMENSION_ORDER = [
    "task_fulfillment_interaction",
    "pronunciation_delivery",
    "fluency",
    "grammar_control",
    "vocabulary_expression",
]

_FREE_TALK_NEXT_ACTIONS = {
    "task_fulfillment_interaction": "질문에 답한 뒤 이유나 예시를 한 문장 더 붙여 대화를 조금 더 확장해 보세요.",
    "pronunciation_delivery": "짧은 핵심 문장을 천천히 또렷하게 읽고 바로 따라 말하는 연습으로 전달력을 높여보세요.",
    "fluency": "답변 시작 전에 연결 표현을 하나 정해 두고 말해 불필요한 멈춤을 줄여보세요.",
    "grammar_control": "자주 쓰는 문장 패턴 2~3개를 통째로 반복해 문법 안정감을 먼저 확보해 보세요.",
    "vocabulary_expression": "같은 뜻을 다른 표현으로 바꿔 말하는 연습을 추가해 표현 범위를 넓혀보세요.",
}

_FREE_TALK_SYSTEM_PROMPT = """You are an expert evaluator for English speaking performance in a language-learning app.

Your job is to score a learner's spoken English response for free conversation or roleplay tasks using the rubric below.
You must evaluate only based on the evidence provided in the transcript, turn context, and optional speech features.
Do not infer abilities that are not observable.
Return valid JSON only. Do not wrap the JSON in markdown.

Evaluation dimensions and weights:
1) Task Fulfillment & Interaction: 30 points
2) Pronunciation & Delivery Clarity: 20 points
3) Fluency: 20 points
4) Grammar Control: 15 points
5) Vocabulary & Expressive Range: 15 points

Scoring levels:
- Level 5 = 100% of dimension weight
- Level 4 = 85% of dimension weight
- Level 3 = 70% of dimension weight
- Level 2 = 50% of dimension weight
- Level 1 = 30% of dimension weight
- Level 0 = 0% of dimension weight

Important anti-overlap rules:
- If the answer is off-task, penalize primarily in Task Fulfillment & Interaction.
- If the learner struggles due to word-search pauses, penalize primarily in Fluency, secondarily in Vocabulary only if clearly supported.
- If grammar errors are frequent but meaning remains clear, penalize primarily in Grammar Control.
- Do not double-penalize the same issue heavily across multiple dimensions.

Score caps:
- If Task Fulfillment & Interaction level is 0, total score cap is 19.
- If Task Fulfillment & Interaction level is 1, total score cap is 49.
- If Task Fulfillment & Interaction level is 2, total score cap is 69.
- If Task Fulfillment & Interaction level is 3 or above, no total score cap applies.

Use this scoring conversion:
- Task Fulfillment & Interaction: [0, 9, 15, 21, 26, 30]
- Pronunciation & Delivery Clarity: [0, 6, 10, 14, 17, 20]
- Fluency: [0, 6, 10, 14, 17, 20]
- Grammar Control: [0, 5, 8, 11, 13, 15]
- Vocabulary & Expressive Range: [0, 5, 8, 11, 13, 15]

Required output rules:
- Include level, score, concise evidence, and learner-facing feedback for each dimension.
- Include total score, overall summary, and exactly 2 next-step action items.
- If pronunciation cannot be reliably judged from the provided evidence, state that clearly in the evidence field and score conservatively.
- Keep feedback specific, observable, and non-judgmental.
- Write evidence, feedback, overall_summary, and next_actions in Korean.

Return JSON with this exact schema:
{
  "version": "speaking_rubric_v1",
  "task_id": "string",
  "scores": {
    "task_fulfillment_interaction": {"level": 0, "score": 0, "evidence": "string", "feedback": "string"},
    "pronunciation_delivery": {"level": 0, "score": 0, "evidence": "string", "feedback": "string"},
    "fluency": {"level": 0, "score": 0, "evidence": "string", "feedback": "string"},
    "grammar_control": {"level": 0, "score": 0, "evidence": "string", "feedback": "string"},
    "vocabulary_expression": {"level": 0, "score": 0, "evidence": "string", "feedback": "string"}
  },
  "total_score": 0,
  "overall_summary": "string",
  "next_actions": ["string", "string"],
  "diagnostics": {
    "applied_total_score_cap": null,
    "confidence": 0.0
  }
}"""


def _safe_int(value: Any, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    try:
        return int(str(value).strip())
    except Exception:
        return default


def _safe_float(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip())
    except Exception:
        return default


def _clip_level(level: Any) -> int:
    return max(0, min(5, _safe_int(level)))


def _count_english_words(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))


def _extract_json_object(raw: str) -> Dict[str, Any]:
    raw = (raw or "").strip()
    if not raw:
        raise ValueError("empty_response")
    try:
        return json.loads(raw)
    except Exception:
        match = re.search(r"\{.*\}", raw, re.S)
        if not match:
            raise
        return json.loads(match.group(0))


def _score_from_level(key: str, level: int) -> int:
    return _FREE_TALK_SCORE_TABLE[key][_clip_level(level)]


def _total_score_cap(task_level: int) -> Optional[int]:
    if task_level == 0:
        return 19
    if task_level == 1:
        return 49
    if task_level == 2:
        return 69
    return None


def _normalize_actions(actions: Any, scores: Dict[str, Dict[str, Any]]) -> List[str]:
    normalized = [
        str(item).strip()
        for item in (actions if isinstance(actions, list) else [])
        if str(item).strip()
    ]
    if len(normalized) >= 2:
        return normalized[:2]

    weakest = sorted(
        _FREE_TALK_DIMENSION_ORDER,
        key=lambda key: (scores[key]["score"], scores[key]["level"]),
    )
    for key in weakest:
        suggestion = _FREE_TALK_NEXT_ACTIONS[key]
        if suggestion not in normalized:
            normalized.append(suggestion)
        if len(normalized) == 2:
            break

    while len(normalized) < 2:
        normalized.append("짧게 말한 뒤 한 문장을 더 덧붙이는 연습으로 답변 확장력을 키워보세요.")
    return normalized[:2]


def _normalize_free_talk_result(result: Dict[str, Any], payload: Dict[str, Any]) -> Dict[str, Any]:
    task = payload.get("task") if isinstance(payload.get("task"), dict) else {}
    scores_in = result.get("scores") if isinstance(result.get("scores"), dict) else {}

    normalized_scores: Dict[str, Dict[str, Any]] = {}
    score_sum = 0
    for key in _FREE_TALK_DIMENSION_ORDER:
        raw_item = scores_in.get(key) if isinstance(scores_in.get(key), dict) else {}
        level = _clip_level(raw_item.get("level"))
        score = _score_from_level(key, level)
        normalized_scores[key] = {
            "level": level,
            "score": score,
            "evidence": str(raw_item.get("evidence") or "제공된 대화 기록을 기준으로 판단했습니다."),
            "feedback": str(raw_item.get("feedback") or "다음 대화에서는 문장을 조금 더 안정적으로 확장해 보세요."),
        }
        score_sum += score

    task_level = normalized_scores["task_fulfillment_interaction"]["level"]
    applied_cap = _total_score_cap(task_level)
    total_score = min(score_sum, applied_cap) if applied_cap is not None else score_sum

    diagnostics_in = result.get("diagnostics") if isinstance(result.get("diagnostics"), dict) else {}
    confidence = _safe_float(diagnostics_in.get("confidence"), 0.65)
    confidence = max(0.0, min(1.0, confidence))

    return {
        "version": "speaking_rubric_v1",
        "task_id": str(result.get("task_id") or task.get("task_id") or "free_talk"),
        "scores": normalized_scores,
        "total_score": total_score,
        "overall_summary": str(
            result.get("overall_summary")
            or "대화 흐름과 문장 확장 정도를 기준으로 프리토킹 수행을 종합 평가했습니다."
        ),
        "next_actions": _normalize_actions(result.get("next_actions"), normalized_scores),
        "diagnostics": {
            "applied_total_score_cap": applied_cap,
            "confidence": round(confidence, 2),
        },
    }


def _fallback_free_talk_score(payload: Dict[str, Any]) -> Dict[str, Any]:
    task = payload.get("task") if isinstance(payload.get("task"), dict) else {}
    response = payload.get("response") if isinstance(payload.get("response"), dict) else {}
    speech = payload.get("speech_features") if isinstance(payload.get("speech_features"), dict) else {}

    transcript = str(response.get("transcript") or "").strip()
    turns = response.get("turns") if isinstance(response.get("turns"), list) else []
    user_turns = [
        str(turn.get("text") or "").strip()
        for turn in turns
        if isinstance(turn, dict)
        and str(turn.get("speaker") or "").lower() == "user"
        and str(turn.get("text") or "").strip()
    ]
    partner_turns = [
        str(turn.get("text") or "").strip()
        for turn in turns
        if isinstance(turn, dict)
        and str(turn.get("speaker") or "").lower() != "user"
        and str(turn.get("text") or "").strip()
    ]

    user_turn_count = max(_safe_int(speech.get("user_turn_count")), len(user_turns))
    words = _count_english_words(transcript)
    unique_words = len(set(re.findall(r"[A-Za-z']+", transcript.lower())))
    total_user_duration_ms = _safe_int(speech.get("total_user_duration_ms"))
    speech_rate_wpm = _safe_float(speech.get("speech_rate_wpm"))
    if speech_rate_wpm <= 0 and total_user_duration_ms > 0:
        speech_rate_wpm = words / max(total_user_duration_ms / 60000, 0.01)

    pause_count = _safe_int(speech.get("pause_count"), -1)
    long_pause_count = _safe_int(speech.get("long_pause_count"), -1)
    intelligibility = _safe_float(speech.get("pronunciation_intelligibility_estimate"), -1)

    avg_words_per_turn = words / max(user_turn_count, 1)
    type_token_ratio = unique_words / max(words, 1)
    response_ratio = min(1.0, user_turn_count / max(len(partner_turns), 1)) if partner_turns else (1.0 if user_turn_count > 0 else 0.0)
    pause_burden = 0.0
    if pause_count >= 0:
        pause_burden += pause_count / max(user_turn_count, 1)
    if long_pause_count >= 0:
        pause_burden += long_pause_count * 1.5 / max(user_turn_count, 1)

    if words < 4 or user_turn_count == 0:
        task_level = 0
    elif user_turn_count == 1 or words < 12:
        task_level = 2
    elif response_ratio >= 0.9 and user_turn_count >= 3 and avg_words_per_turn >= 8:
        task_level = 4
    else:
        task_level = 3

    if intelligibility >= 0.9:
        pronunciation_level = 5
    elif intelligibility >= 0.82:
        pronunciation_level = 4
    elif intelligibility >= 0.72:
        pronunciation_level = 3
    elif intelligibility >= 0.6:
        pronunciation_level = 2
    elif intelligibility >= 0:
        pronunciation_level = 1
    elif words >= 20 and user_turn_count >= 2:
        pronunciation_level = 3
    elif words >= 8:
        pronunciation_level = 2
    else:
        pronunciation_level = 1

    if words < 4:
        fluency_level = 0
    elif 85 <= speech_rate_wpm <= 150 and pause_burden <= 2.5:
        fluency_level = 4
    elif 70 <= speech_rate_wpm <= 170:
        fluency_level = 3
    elif speech_rate_wpm > 0:
        fluency_level = 2
    else:
        fluency_level = 1

    grammar_markers = len(re.findall(r"\b(because|if|when|but|so|that)\b", transcript.lower()))
    if words < 5:
        grammar_level = 0
    elif avg_words_per_turn >= 8 and grammar_markers >= 1:
        grammar_level = 4
    elif avg_words_per_turn >= 5:
        grammar_level = 3
    else:
        grammar_level = 2

    if words < 5:
        vocab_level = 0
    elif unique_words >= 30 and type_token_ratio >= 0.55:
        vocab_level = 4
    elif unique_words >= 15 and type_token_ratio >= 0.4:
        vocab_level = 3
    else:
        vocab_level = 2

    scores = {
        "task_fulfillment_interaction": {
            "level": task_level,
            "score": _score_from_level("task_fulfillment_interaction", task_level),
            "evidence": f"사용자 발화 {user_turn_count}회, 총 {words}단어 기준으로 질문에 반응하며 대화를 이어간 정도를 평가했습니다.",
            "feedback": "답변 뒤에 이유나 예시를 한 문장 더 붙이면 상호작용 점수를 더 끌어올릴 수 있습니다.",
        },
        "pronunciation_delivery": {
            "level": pronunciation_level,
            "score": _score_from_level("pronunciation_delivery", pronunciation_level),
            "evidence": intelligibility >= 0
                and f"제공된 intelligibility 추정치 {intelligibility:.2f}를 반영했습니다."
                or "오디오 기반 발음 평가는 없어서 전사 안정성과 대화 지속 여부를 기준으로 보수적으로 평가했습니다.",
            "feedback": "짧은 핵심 문장을 천천히 또렷하게 반복해서 말하면 전달 명료도를 높이는 데 도움이 됩니다.",
        },
        "fluency": {
            "level": fluency_level,
            "score": _score_from_level("fluency", fluency_level),
            "evidence": f"말하기 속도는 약 {speech_rate_wpm:.1f} WPM이며, 제공된 멈춤 정보와 턴 길이를 함께 봤습니다.",
            "feedback": "답변 시작 전에 연결 표현을 정해 두고 말하면 불필요한 멈춤을 줄일 수 있습니다.",
        },
        "grammar_control": {
            "level": grammar_level,
            "score": _score_from_level("grammar_control", grammar_level),
            "evidence": f"턴당 평균 {avg_words_per_turn:.1f}단어와 문장 연결 표현 사용 정도를 바탕으로 문장 안정성을 평가했습니다.",
            "feedback": "자주 쓰는 문장 패턴을 통째로 반복해 두면 문법 정확성을 더 안정적으로 유지할 수 있습니다.",
        },
        "vocabulary_expression": {
            "level": vocab_level,
            "score": _score_from_level("vocabulary_expression", vocab_level),
            "evidence": f"고유 어휘 {unique_words}개, type-token ratio {type_token_ratio:.2f} 기준으로 표현 다양성을 평가했습니다.",
            "feedback": "같은 의미를 다른 표현으로 바꿔 말하는 연습을 추가하면 어휘 및 표현 범위가 넓어집니다.",
        },
    }

    total = sum(item["score"] for item in scores.values())
    confidence = 0.55
    if user_turn_count >= 3:
        confidence += 0.1
    if total_user_duration_ms >= 30000:
        confidence += 0.1
    if intelligibility >= 0:
        confidence += 0.1
    if pause_count >= 0:
        confidence += 0.05

    weakest = sorted(
        _FREE_TALK_DIMENSION_ORDER,
        key=lambda key: scores[key]["score"],
    )

    return {
        "version": "speaking_rubric_v1",
        "task_id": str(task.get("task_id") or "free_talk"),
        "scores": scores,
        "total_score": total,
        "overall_summary": "대화를 유지하는 능력은 확인됐고, 더 높은 점수를 위해서는 답변 확장과 말하기 안정감을 함께 끌어올리는 것이 중요합니다.",
        "next_actions": [
            _FREE_TALK_NEXT_ACTIONS[weakest[0]],
            _FREE_TALK_NEXT_ACTIONS[weakest[1 if len(weakest) > 1 else 0]],
        ],
        "diagnostics": {
            "applied_total_score_cap": _total_score_cap(task_level),
            "confidence": min(confidence, 0.9),
        },
    }


def _llm_free_talk_score(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    try:
        client = _get_client()
        model = os.getenv("OPENAI_SCORING_MODEL") or "gpt-5-nano"
        resp = client.chat.completions.create(
            model=model,
            temperature=0.2,
            messages=[
                {"role": "system", "content": _FREE_TALK_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": "Evaluate the following learner conversation payload.\n"
                    + json.dumps(payload, ensure_ascii=False),
                },
            ],
        )
        content = resp.choices[0].message.content or ""
        return _extract_json_object(content)
    except Exception as e:
        log.warning(f"LLM free-talk scoring failed: {e}", trace_id="-")
        return None


@app.post("/speaking/free-talk/score")
async def speaking_free_talk_score(payload: dict = Body(...)):
    task = payload.get("task") if isinstance(payload.get("task"), dict) else {}
    response = payload.get("response") if isinstance(payload.get("response"), dict) else {}
    transcript = str(response.get("transcript") or "").strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="response.transcript is required")

    if not task.get("task_id"):
        payload.setdefault("task", {})
        payload["task"]["task_id"] = f"free_talk_{int(time.time())}"

    scored = _llm_free_talk_score(payload) or _fallback_free_talk_score(payload)
    return _normalize_free_talk_result(scored, payload)

# --- 병합 리포트 ---
# 다른 파일에서 추가된 라우트: [('http', 'post', '/toeic/generate'), ('http', 'post', '/toeic/grade')]
# 중복으로 건너뛴 라우트: [('event', 'startup'), ('http', 'get', '/healthz'), ('http', 'post', '/speech/turn')]
# --------------------



# ===== Merged from main(7).py (non-conflicting symbols only; comments preserved) =====

# ⚠️ 병합 섹션 안내
# 이 아래 블록은 main(7).py에서 자동 병합된 최소 예제 라우트입니다.
# 상단의 정식 구현과 기능이 중복될 수 있으니 운영 환경에서는 한쪽만 유지하세요.

#

# 추가 import
 # [NEW] 롤플레이 생성 기능 스키마 import
 # - /roleplay/generate 엔드포인트 요청/응답 모델
from app.schemas import RoleplayCatalogResponse, RoleplayGenerateRequest, RoleplayGenerateResponse
from app.services.roleplay import generate as roleplay_generate, get_catalog as roleplay_get_catalog



@app.get("/roleplay/catalog", response_model=RoleplayCatalogResponse)
async def roleplay_catalog_api():
    return roleplay_get_catalog()


# ====== NEW ======
# Roleplay 생성 API(services.roleplay.generate 위임)
# - 요청/응답 스키마는 app.schemas의 RoleplayGenerateRequest/Response를 따릅니다.
 # [NEW] 롤플레이 생성 API
 # - 세션이 없으면 내부에서 생성, 이후 services.roleplay.generate 로 위임
 # - 사용처: 대화형 롤플레이 연습(시나리오/턴 진행)
@app.post("/roleplay/generate", response_model=RoleplayGenerateResponse)
async def roleplay_generate_api(payload: RoleplayGenerateRequest = Body(...)):
    """
    세션 없는 첫 호출도 허용.
    - session_id 없으면 새 세션 생성 후 INTRO/시나리오 생성
    - 이후 호출부터 user_input과 함께 턴 진행
    - pace에 따라 chunks 길이 조절
    """
    return await roleplay_generate(payload)


# === Added imports from main(8).py (auto-merged, keep if used) ===
# [설명] 이 블록은 이번 주 추가된 Pattern Drill/Paraphrase 기능을 위해 필요한 의존성입니다.
#  - app.schemas.* : FastAPI가 바디를 자동 검증/문서화하는 Pydantic 모델(요청/응답 스키마)
#  - app.services.llm : LLM 사용 가능 시 프롬프트 기반 JSON 응답을 생성하는 유틸(불가 시 목업으로 폴백)
#  - app.services.eval.score_answer : 사용자의 문장을 참조 정답들과 비교해 유사도를 계산하는 채점 함수
from app.schemas import PatternDrillRequest, PatternDrillGenerateResponse, PatternDrillScoreResponse, ParaphraseRequest, ParaphraseResponse
from app.services import llm
from app.services.eval import score_answer


# === Added definitions from main(8).py (auto-merged) ===
# === Added from main(8).py: pattern_drill ===
# [설명] Pattern Drill 핵심 로직
#  - task="generate" : 패턴과 컨텍스트/개수를 입력받아 문항(prompt)과 허용 정답(answers)을 생성
#      · 우선 LLM을 호출해 JSON을 생성하고, 실패/미가용 시 간단한 목업 데이터로 폴백
#  - task="score"    : 사용자 답과 참조 정답 목록을 비교해 유사도 점수와 합격여부(pass)를 산출
#      · score_answer() 유틸을 사용하며, tolerance(기본 ~0.70)를 임계값으로 사용
#  - 반환 형식은 app.schemas의 PatternDrillGenerateResponse / PatternDrillScoreResponse를 따름
def pattern_drill(req: PatternDrillRequest):
    # --- GENERATE ---
    if req.task == "generate":
        if llm.is_llm_available():
            system = open("config/prompts/pattern_drill_v1.md", "r", encoding="utf-8").read()
            user = f"""pattern: {req.pattern}
context: {req.context or "-"}
count: {req.count}
Return JSON following the contract.
"""
            data = llm.chat_json(system, user, temperature=0.4)
            if data and "items" in data:
                return PatternDrillGenerateResponse(items=data["items"])
        # fallback mock generation (요청 개수 보장)
        base = [
            {"prompt": f"Use '{req.pattern}' to invite a friend politely.",
             "answers": ["Would you like to join us?", "Would you like to come along?"]},
            {"prompt": f"Make a suggestion with '{req.pattern}'.",
             "answers": ["How about taking a break?", "How about going for a walk?"]},
        ]
        # req.count 가 base 길이보다 크면 간단한 변형으로 채워서 항상 req.count개 반환
        items = list(base)
        need = max(1, req.count) - len(items)
        i = 0
        while need > 0:
            i += 1
            ctx = f" (ctx: {req.context})" if req.context else ""
            items.append({
                "prompt": f"Practice using '{req.pattern}'{ctx} — variation {i}.",
                "answers": [
                    f"{req.pattern.replace('~', 'to try option ' + str(i)) if '~' in req.pattern else 'Would you like to try option ' + str(i) }",
                    f"{req.pattern.replace('~', 'to consider choice ' + str(i)) if '~' in req.pattern else 'Would you like to consider choice ' + str(i) }",
                ],
            })
            need -= 1
        return PatternDrillGenerateResponse(items=items[:max(1, req.count)])
    # --- SCORE ---
    elif req.task == "score":
        if not req.user_answer or not req.reference_answers:
            raise HTTPException(status_code=400, detail="user_answer and reference_answers are required for scoring.")
        sc, best = score_answer(req.user_answer, req.reference_answers)
        passed = sc >= req.tolerance
        reasons = [f"similarity={sc:.2f} (threshold {req.tolerance:.2f})",
                   f"best_match='{best}'"]
        return PatternDrillScoreResponse(score=sc, **{"pass": passed}, reasons=reasons, best_match=best, used_tolerance=req.tolerance)
    else:
        raise HTTPException(status_code=400, detail="Unknown task")

# Helper for deterministic paraphrase variants (fallback)
def _paraphrase_variants(text: str, tone: str, length: str, n: int):
    """Generate n simple paraphrase candidates deterministically (fallback).
    - tone: polite/formal/friendly/casual/academic/concise
    - length: shorter/same/longer
    """
    base = (text or "").strip()
    out = []

    def tone_transform(s: str, i: int) -> str:
        if tone in ("polite", "formal"):
            # ensure polite phrasing
            if not re.search(r"(?i)\bplease\b", s):
                s = ("Please " + s[0].lower() + s[1:]) if s else "Please."
        elif tone in ("friendly", "casual"):
            starters = ["Hey,", "Just a heads up,", "FYI,", "Hey there,"]
            if s:
                s = f"{starters[i % len(starters)]} {s[0].lower() + s[1:]}"
            else:
                s = starters[i % len(starters)]
        elif tone == "academic":
            s = re.sub(r"(?i)\b(I think|maybe|I guess)\b", "It appears that", s)
        elif tone == "concise":
            s = re.sub(r"(?i)\b(very|really|just|kind of|sort of)\b", "", s)
            s = re.sub(r"\s+", " ", s).strip()
        return s

    def length_transform(s: str, i: int) -> str:
        if length == "shorter":
            words = s.split()
            if len(words) > 10:
                s = " ".join(words[:10]) + "..."
        elif length == "longer":
            suffixes = [
                " Thanks for understanding.",
                " I appreciate your patience.",
                " If that's okay with you.",
                " I apologize for any inconvenience.",
                " Please let me know if that works.",
            ]
            s = s.rstrip(".") + suffixes[i % len(suffixes)]
        return s

    total = max(1, min(5, int(n)))
    for i in range(total):
        s = base
        s = tone_transform(s, i)
        s = length_transform(s, i)
        out.append({"text": s, "tone": tone, "length": length})
    return out

def paraphrase(req: ParaphraseRequest):
    if llm.is_llm_available():
        system = open("config/prompts/paraphrase_v1.md", "r", encoding="utf-8").read()
        user = f"""text: {req.text}
tone: {req.tone}
length: {req.length}
n: {req.n}
Return JSON following the contract."""
        data = llm.chat_json(system, user, temperature=0.7)
        if data and "candidates" in data:
            # Normalize and ensure at least n candidates
            raw = list(data["candidates"] or [])
            norm = []
            for c in raw:
                if isinstance(c, dict):
                    txt = str(c.get("text", "")).strip()
                    if not txt:
                        continue
                    t = c.get("tone") or req.tone
                    l = c.get("length") or req.length
                    norm.append({"text": txt, "tone": t, "length": l})
            if len(norm) < req.n:
                fill = _paraphrase_variants(req.text, req.tone, req.length, req.n - len(norm))
                norm.extend(fill)
            return ParaphraseResponse(candidates=norm[:req.n], meta={"llm": "on"})

    # fallback mock (deterministic) — always return exactly req.n items
    variants = _paraphrase_variants(req.text, req.tone, req.length, req.n)
    return ParaphraseResponse(candidates=variants[:req.n], meta={"llm": "mock"})

# === Route wrappers (expose helpers as HTTP endpoints) ===
# [설명] 위의 로직 함수(pattern_drill/paraphrase)를 실제 HTTP 엔드포인트로 노출하는 래퍼입니다.
#  - 경로: POST /pattern/drill, POST /paraphrase  (Flutter의 신규 탭이 이 경로로 호출)
#  - 요청 바디: 각각 PatternDrillRequest / ParaphraseRequest (자동 검증)
#  - 주의: 함수명/경로를 변경하면 앱 탭 호출이 404가 됩니다. 로직은 위 헬퍼에 위임합니다.
@app.post("/pattern/drill")
def pattern_drill_api(req: PatternDrillRequest):
    """Thin wrapper: delegates to the helper while keeping original logic and comments."""
    return pattern_drill(req)

@app.post("/paraphrase")
def paraphrase_api(req: ParaphraseRequest):
    return paraphrase(req)


# === Merged additions from main(9).py ===

# 임베딩/벡터스토어 초기화 (설정 미존재 시 안전한 기본값)
# (신규) Mistake 학습기록을 복습(SRS)과 검색(FAISS) 양쪽에 재활용하기 위해
#   서버 부팅 시점에서 임베더·벡터 스토어를 미리 구성합니다.
#   - EMBED_DIM: 설정에 없으면 384로 고정해 클라이언트/서버 차원의 차원 불일치 위험을 줄였습니다.
#   - VECTOR_ROOT: 로컬 경로(server/data/vector)를 기본값으로 두어 docker/로컬 환경 모두 동일 구조를 사용합니다.
#   - EMBED_PROVIDER: 설정값이 없으면 해시 기반 모의 임베더를 써서 개발 환경에서도 API가 깨지지 않도록 했습니다.
# 결과적으로 이후 Mistake/검색 엔드포인트에서 동일 싱글턴을 공유해 초기화 비용을 최소화합니다.
EMBED_DIM = getattr(settings, "EMBED_DIM", 384)
VECTOR_ROOT = getattr(settings, "VECTOR_ROOT", "server/data/vector")
EMBED_PROVIDER = getattr(settings, "EMBED_PROVIDER", "hash")
_embedder = build_embedder(EMBED_PROVIDER, EMBED_DIM)
_vstore = VectorStore(VECTOR_ROOT, EMBED_DIM)
_vocab_seed_path = Path(__file__).resolve().parents[1] / "dictionaries" / "vocab_seed.json"
_vocab_again_queue: deque[int] = deque(maxlen=200)
_vocab_mcq_recent: dict[str, deque[int]] = {
    "beginner": deque(maxlen=60),
    "intermediate": deque(maxlen=60),
    "advanced": deque(maxlen=60),
}


def _direction_by_difficulty(difficulty: int) -> str:
    if difficulty <= 1:
        return "word_to_meaning"
    if difficulty == 2:
        return "meaning_to_word"
    return random.choice(["word_to_meaning", "meaning_to_word"])


def _difficulty_by_level(level: str) -> int:
    return {"beginner": 1, "intermediate": 2, "advanced": 3}[level]


def _level_by_difficulty(difficulty: int) -> str:
    if difficulty <= 1:
        return "beginner"
    if difficulty == 2:
        return "intermediate"
    return "advanced"


def _pick_unique_choices(correct: str, distractors: list[str]) -> tuple[list[str], int]:
    pool = [d for d in distractors if d and d != correct]
    random.shuffle(pool)
    choices = [correct]
    for item in pool:
        if item not in choices:
            choices.append(item)
        if len(choices) == 4:
            break
    while len(choices) < 4:
        filler = f"(placeholder {len(choices)})"
        if filler not in choices:
            choices.append(filler)
    random.shuffle(choices)
    return choices, choices.index(correct)


def _load_vocab_seed() -> list[dict[str, Any]]:
    if not _vocab_seed_path.exists():
        return []
    with _vocab_seed_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        return []
    return [item for item in data if isinstance(item, dict)]


async def _ensure_vocab_catalog(db: AsyncSession, min_per_level: int = 200) -> int:
    stale_count = await db.scalar(
        select(func.count(VocabCard.id)).where(
            VocabCard.source == "builtin",
            VocabCard.meaning_ko.like("%관련 의미%"),
        )
    )
    if int(stale_count or 0) > 0:
        await db.execute(delete(VocabCard).where(VocabCard.source == "builtin"))
        await db.commit()

    level_counts = await db.execute(
        select(VocabCard.difficulty, func.count(VocabCard.id)).group_by(VocabCard.difficulty)
    )
    count_map = {int(d): int(c) for d, c in level_counts.all()}
    if all(count_map.get(d, 0) >= min_per_level for d in (1, 2, 3)):
        total_now = await db.scalar(select(func.count(VocabCard.id)))
        return int(total_now or 0)

    seed_items = _load_vocab_seed()
    if not seed_items:
        total_now = await db.scalar(select(func.count(VocabCard.id)))
        return int(total_now or 0)

    imported = 0
    for item in seed_items:
        lemma = str(item.get("lemma", "")).strip()
        meaning_ko = str(item.get("meaning_ko", "")).strip()
        if not lemma or not meaning_ko:
            continue
        exists = await db.scalar(
            select(VocabCard.id).where(
                VocabCard.lemma == lemma,
                VocabCard.meaning_ko == meaning_ko,
                VocabCard.source == "builtin",
            )
        )
        if exists:
            continue
        card = VocabCard(
            user_id=None,
            lemma=lemma,
            meaning_ko=meaning_ko,
            example_en=str(item.get("example_en", "")).strip() or None,
            difficulty=max(1, min(3, int(item.get("difficulty", 2)))),
            source="builtin",
            tags=str(item.get("tags", "")).strip() or None,
            pos=str(item.get("pos", "")).strip() or None,
        )
        db.add(card)
        await db.flush()
        await ensure_vocab_state(db, card.id)
        imported += 1
    if imported > 0:
        await db.commit()
    total_after = await db.scalar(select(func.count(VocabCard.id)))
    return int(total_after or 0)


@app.post("/vocab/cards", response_model=VocabCardOut)
async def create_vocab_card(payload: VocabCardCreate, db: AsyncSession = Depends(get_session)):
    card = VocabCard(
        user_id=payload.user_id,
        lemma=payload.lemma.strip(),
        meaning_ko=payload.meaning_ko.strip(),
        example_en=(payload.example_en or "").strip() or None,
        difficulty=payload.difficulty,
        source="manual",
        tags=(payload.tags or "").strip() or None,
        pos=(payload.pos or "").strip() or None,
    )
    db.add(card)
    await db.flush()
    await ensure_vocab_state(db, card.id)
    await db.commit()
    await db.refresh(card)
    return card


@app.get("/vocab/cards", response_model=list[VocabCardOut])
async def list_vocab_cards(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_session),
):
    q = await db.execute(
        select(VocabCard).order_by(VocabCard.id.desc()).offset(offset).limit(limit)
    )
    return q.scalars().all()


@app.get("/vocab/cards/{card_id}", response_model=VocabCardOut)
async def get_vocab_card(card_id: int, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    return card


@app.patch("/vocab/cards/{card_id}", response_model=VocabCardOut)
async def update_vocab_card(card_id: int, payload: VocabCardUpdate, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    fields = payload.model_dump(exclude_unset=True)
    for key, value in fields.items():
        if isinstance(value, str):
            value = value.strip() or None
        setattr(card, key, value)
    await db.commit()
    await db.refresh(card)
    return card


@app.delete("/vocab/cards/{card_id}")
async def delete_vocab_card(card_id: int, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    await db.delete(card)
    await db.commit()
    return {"ok": True, "card_id": card_id}


@app.post("/vocab/cards/import", response_model=VocabImportResult)
async def import_vocab_cards(payload: VocabImportRequest, db: AsyncSession = Depends(get_session)):
    candidates = _load_vocab_seed()
    if payload.level:
        wanted_difficulty = _difficulty_by_level(payload.level)
        candidates = [x for x in candidates if int(x.get("difficulty", wanted_difficulty)) == wanted_difficulty]
    if payload.category:
        category = payload.category.strip().lower()
        candidates = [x for x in candidates if str(x.get("category", "")).strip().lower() == category]
    candidates = candidates[: payload.limit]

    imported = 0
    skipped = 0
    for item in candidates:
        lemma = str(item.get("lemma", "")).strip()
        meaning_ko = str(item.get("meaning_ko", "")).strip()
        if not lemma or not meaning_ko:
            skipped += 1
            continue
        exists = await db.scalar(
            select(VocabCard).where(
                VocabCard.lemma == lemma,
                VocabCard.meaning_ko == meaning_ko,
                VocabCard.source == "builtin",
            )
        )
        if exists:
            skipped += 1
            continue
        card = VocabCard(
            user_id=payload.user_id,
            lemma=lemma,
            meaning_ko=meaning_ko,
            example_en=str(item.get("example_en", "")).strip() or None,
            difficulty=int(item.get("difficulty", 2)),
            source="builtin",
            tags=str(item.get("tags", "")).strip() or None,
            pos=str(item.get("pos", "")).strip() or None,
        )
        db.add(card)
        await db.flush()
        await ensure_vocab_state(db, card.id)
        imported += 1
    await db.commit()
    return VocabImportResult(
        imported=imported,
        skipped=skipped,
        total_candidates=len(candidates),
    )


@app.get("/vocab/srs/next", response_model=list[VocabSRSItem])
async def vocab_srs_next(
    limit: int = Query(20, ge=1, le=100),
    level: Optional[VocabLevel] = Query(default=None),
    db: AsyncSession = Depends(get_session),
):
    await _ensure_vocab_catalog(db, min_per_level=200)
    now = datetime.now(timezone.utc)
    target_diff = _difficulty_by_level(level) if level else None
    items: list[VocabSRSItem] = []
    queued: set[int] = set()

    while _vocab_again_queue and len(items) < limit:
        cid = _vocab_again_queue.pop()
        if cid in queued:
            continue
        row = await db.execute(
            select(VocabCard, VocabSRSState)
            .join(VocabSRSState, VocabSRSState.card_id == VocabCard.id)
            .where(VocabCard.id == cid)
        )
        got = row.first()
        if not got:
            continue
        card, state = got
        if target_diff and card.difficulty != target_diff:
            continue
        items.append(
            VocabSRSItem(
                card_id=card.id,
                lemma=card.lemma,
                meaning_ko=card.meaning_ko,
                example_en=card.example_en,
                difficulty=card.difficulty,
                due_at=state.due_at,
                direction=_direction_by_difficulty(card.difficulty),
            )
        )
        queued.add(cid)

    remaining = limit - len(items)
    if remaining > 0:
        due_query = (
            select(VocabCard, VocabSRSState)
            .join(VocabSRSState, VocabSRSState.card_id == VocabCard.id)
            .where(VocabSRSState.due_at <= now)
        )
        if target_diff:
            due_query = due_query.where(VocabCard.difficulty == target_diff)
        rows = await db.execute(due_query.limit(500))
        due_candidates = rows.all()
        random.shuffle(due_candidates)
        for card, state in due_candidates[:remaining]:
            if card.id in queued:
                continue
            items.append(
                VocabSRSItem(
                    card_id=card.id,
                    lemma=card.lemma,
                    meaning_ko=card.meaning_ko,
                    example_en=card.example_en,
                    difficulty=card.difficulty,
                    due_at=state.due_at,
                    direction=_direction_by_difficulty(card.difficulty),
                )
            )
            queued.add(card.id)

    remaining = limit - len(items)
    if remaining > 0:
        fill_query = (
            select(VocabCard, VocabSRSState)
            .join(VocabSRSState, VocabSRSState.card_id == VocabCard.id)
        )
        if target_diff:
            fill_query = fill_query.where(VocabCard.difficulty == target_diff)
        fill_rows = await db.execute(fill_query.limit(500))
        fill_candidates = fill_rows.all()
        random.shuffle(fill_candidates)
        for card, state in fill_candidates:
            if len(items) >= limit:
                break
            if card.id in queued:
                continue
            items.append(
                VocabSRSItem(
                    card_id=card.id,
                    lemma=card.lemma,
                    meaning_ko=card.meaning_ko,
                    example_en=card.example_en,
                    difficulty=card.difficulty,
                    due_at=state.due_at,
                    direction=_direction_by_difficulty(card.difficulty),
                )
            )
            queued.add(card.id)
    return items


@app.post("/vocab/srs/review", response_model=VocabReviewOut)
async def vocab_srs_review(payload: VocabReviewIn, db: AsyncSession = Depends(get_session)):
    card = await db.get(VocabCard, payload.card_id)
    if not card:
        raise HTTPException(status_code=404, detail="vocab card not found")
    state, quality = await apply_vocab_review(db, payload.card_id, payload.grade)
    if payload.grade == "again":
        _vocab_again_queue.append(payload.card_id)
    await db.commit()
    return VocabReviewOut(
        card_id=payload.card_id,
        grade=payload.grade,
        quality=quality,
        next_due_at=state.due_at,
        ease=state.ease,
        interval_days=state.interval_days,
        reps=state.reps,
    )


@app.get("/vocab/quiz/mcq/next", response_model=list[VocabMCQItem])
async def vocab_mcq_next(
    limit: int = Query(10, ge=1, le=50),
    level: VocabLevel = Query("beginner"),
    card_ids: Optional[List[int]] = Query(default=None),
    db: AsyncSession = Depends(get_session),
):
    await _ensure_vocab_catalog(db, min_per_level=200)
    picked: list[VocabCard] = []

    if card_ids:
        selected_ids: list[int] = []
        seen_ids: set[int] = set()
        for cid in card_ids:
            if cid in seen_ids:
                continue
            seen_ids.add(cid)
            selected_ids.append(cid)
            if len(selected_ids) >= limit:
                break

        if selected_ids:
            rows = await db.execute(select(VocabCard).where(VocabCard.id.in_(selected_ids)))
            by_id = {card.id: card for card in rows.scalars().all()}
            picked = [by_id[cid] for cid in selected_ids if cid in by_id]
    else:
        diff = _difficulty_by_level(level)
        recent = set(_vocab_mcq_recent[level])
        rows = await db.execute(
            select(VocabCard)
            .where(VocabCard.difficulty == diff)
            .order_by(VocabCard.id.desc())
            .limit(300)
        )
        cards = rows.scalars().all()
        pool = [c for c in cards if c.id not in recent]
        if len(pool) < limit:
            pool = cards
        random.shuffle(pool)
        picked = pool[:limit]

    out: list[VocabMCQItem] = []
    for card in picked:
        direction = _direction_by_difficulty(card.difficulty)
        if card.difficulty <= 1:
            direction = "word_to_meaning"
        elif card.difficulty == 2:
            direction = "meaning_to_word"

        distractor_query = (
            select(VocabCard)
            .where(VocabCard.difficulty == card.difficulty)
            .where(VocabCard.id != card.id)
        )
        if card.pos:
            distractor_query = distractor_query.where(VocabCard.pos == card.pos)
        distractors_rows = await db.execute(distractor_query.limit(80))
        distractor_cards = distractors_rows.scalars().all()
        if len(distractor_cards) < 3:
            fallback = await db.execute(
                select(VocabCard)
                .where(VocabCard.id != card.id)
                .order_by(VocabCard.id.desc())
                .limit(120)
            )
            distractor_cards = fallback.scalars().all()

        if direction == "word_to_meaning":
            choices, answer_index = _pick_unique_choices(
                card.meaning_ko,
                [c.meaning_ko for c in distractor_cards],
            )
            out.append(
                VocabMCQItem(
                    card_id=card.id,
                    level=_level_by_difficulty(card.difficulty),
                    direction=direction,
                    question_text=card.lemma,
                    choices=choices[:4],
                    answer_index=answer_index,
                )
            )
        else:
            choices, answer_index = _pick_unique_choices(
                card.lemma,
                [c.lemma for c in distractor_cards],
            )
            out.append(
                VocabMCQItem(
                    card_id=card.id,
                    level=_level_by_difficulty(card.difficulty),
                    direction=direction,
                    question_text=card.meaning_ko,
                    choices=choices[:4],
                    answer_index=answer_index,
                )
            )
        if not card_ids:
            _vocab_mcq_recent[level].append(card.id)
    return out

# --- SRS/Mistake/Vector API endpoints ---

 # [NEW] Mistake 생성 + (옵션) 벡터 인덱싱
 # - DB에 오답을 저장하고, index=True면 텍스트+교정을 임베딩 후 네임스페이스에 upsert
 # - ensure_initial_state()로 SRS 초기 상태를 보장(due_at 등)
@app.post("/mistakes", response_model=MistakeOut)
async def create_mistake(payload: MistakeCreate, db: AsyncSession = Depends(get_session)):
    # (신규) Mistake 생성 흐름 상세
    #   1) 사용자가 제출한 문장/교정/난이도 정보를 Mistake 테이블에 저장
    #   2) ensure_initial_state()를 호출해 동일 트랜잭션 안에서 SRSState(due_at 등)까지 세팅
    #   3) payload.index=true라면 텍스트+교정을 결합한 임베딩을 계산해 namespace별 벡터 인덱스에 업서트
    #      → 추후 /mistakes/search나 /index/query에서 바로 검색 가능
    #   4) commit 이전에 flush를 호출해 Mistake ID를 확보, VSItem ref_id에 `mistake:{id}` 규칙으로 저장
    # 이렇게 해 두면 Mistake 작성 → SRS 카드 생성 → 선택적 벡터 인덱싱이 한 번의 API 호출로 끝납니다.
    m = Mistake(
        user_id=payload.user_id, text=payload.text, correction=payload.correction,
        tags=payload.tags, difficulty=payload.difficulty, prompt_id=payload.prompt_id
    )
    db.add(m)
    await db.flush()
    state = await ensure_initial_state(db, m)

    # 인덱싱 옵션
    if payload.index:
        text_for_emb = payload.text + (" " + payload.correction if payload.correction else "")
        emb = await _embedder.embed([text_for_emb])  # (1, dim)
        # [NEW] shape guard: ensure (1, dim) for FAISS/NumPy
        if getattr(emb, "ndim", 2) == 1:
            emb = emb.reshape(1, -1)
        await _vstore.upsert(
            payload.namespace,
            emb,
            [VSItem(ref_id=f"mistake:{m.id}", text=payload.text, meta={"mistake_id": m.id, "tags": payload.tags})],
        )

    await db.commit()
    return MistakeOut(id=m.id, text=m.text, correction=m.correction, tags=m.tags, due_at=state.due_at)

 # [NEW] SRS 대기열 조회
 # - 지금 복습해야 할 카드(due_at <= now)를 오래된 순으로 최대 limit개 반환
@app.get("/srs/next", response_model=list[SRSItem])
async def srs_next(limit: int = 20, db: AsyncSession = Depends(get_session)):
    # (신규) SRS가 지금 복습해야 할 카드만 선별해 클라이언트가 바로 퀴즈 UI에 바인딩할 수 있게 합니다.
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    q = await db.execute(
        select(Mistake, SRSState).join(SRSState, SRSState.mistake_id == Mistake.id)
        .where(SRSState.due_at <= now).order_by(SRSState.due_at.asc()).limit(limit)
    )
    rows = q.all()
    return [SRSItem(id=m.id, text=m.text, correction=m.correction, due_at=s.due_at) for (m, s) in rows]

 # [NEW] SRS 리뷰 반영
 # - quality(0~5)에 따라 SM-2 유사 규칙으로 interval/ease/due_at 갱신
@app.post("/srs/review", response_model=MistakeOut)
async def srs_review(payload: ReviewIn, db: AsyncSession = Depends(get_session)):
    # (신규) 학습자가 제출한 품질 점수를 기반으로 SM2 스타일 스케줄을 업데이트하도록 엔드포인트를 노출했습니다.
    m = await db.get(Mistake, payload.mistake_id)
    if not m:
        raise HTTPException(404, "mistake not found")
    state = await apply_review(db, payload.mistake_id, payload.quality)
    await db.commit()
    return MistakeOut(id=m.id, text=m.text, correction=m.correction, tags=m.tags, due_at=state.due_at)

 # [NEW] 벡터 인덱스 Upsert API
 # - 임의 ref_id/text/meta 리스트를 받아 임베딩 후 인덱스에 삽입/갱신
@app.post("/index/upsert")
async def index_upsert(req: UpsertReq):
    # (신규) Mistake 외의 데이터도 동일한 벡터 인덱스에 삽입할 수 있도록 범용 업서트 API를 열었습니다.
    texts = [it.text for it in req.items]
    emb = await _embedder.embed(texts)
    # [NEW] shape guard: handle single-text case → (1, dim)
    if getattr(emb, "ndim", 2) == 1:
        emb = emb.reshape(1, -1)
    items = [VSItem(ref_id=it.ref_id, text=it.text, meta=it.meta) for it in req.items]
    await _maybe_await(_vstore.upsert(req.namespace, emb, items))
    return {"ok": True, "count": len(items)}

 # [NEW] 벡터 쿼리 API
 # - query 문자열을 (1, d) 임베딩으로 만들어 top_k 최근접 이웃 반환
@app.post("/index/query")
async def index_query(req: QueryReq):
    # FAISS는 (n, d) 2D 행렬을 기대하므로 (1, dim) 2D를 그대로 전달
    # (신규) 프론트엔드가 자체 쿼리 문자열만 주고 바로 벡터 검색 결과를 받을 수 있게 했습니다.
    qemb = await _embedder.embed([req.query])  # (1, dim)
    # [NEW] shape guard: avoid faiss.normalize_L2 IndexError for 1D array
    if getattr(qemb, "ndim", 2) == 1:
        qemb = qemb.reshape(1, -1)
    hits = await _maybe_await(_vstore.query(req.namespace, qemb, top_k=req.top_k))
    return {"ok": True, "hits": hits}

 # [NEW] 인덱스 통계 API
 # - 전체 벡터 수/차원/네임스페이스 상태를 요약해 반환
@app.get("/index/stats")
async def index_stats():
    return await _maybe_await(_vstore.stats())

# === Vector ↔ DB bridge: rebuild & search ===

 # [NEW] 전체 재색인(Rebuild) API
 # - DB의 Mistake 전량을 배치로 읽어 임베딩 → 인덱스 초기화/재구성
@app.post("/index/rebuild")
async def index_rebuild(
    namespace: str = Body("mistakes"),
    batch_size: int = Body(64),
    db: AsyncSession = Depends(get_session),
):
    """
    DB의 Mistake 전량을 읽어 벡터 인덱스를 재구성합니다.
    - namespace: 인덱스 네임스페이스(기본 'mistakes')
    - batch_size: 임베딩/업서트 배치 크기
    """
    # (신규) 장애 복구나 임베딩 파라미터 변경 시 전체 Mistake를 다시 벡터화하는 관리용 엔드포인트입니다.
    total = 0
    offset = 0
    while True:
        res = await db.execute(
            select(Mistake)
            .order_by(Mistake.id.asc())
            .offset(offset)
            .limit(batch_size)
        )
        ms = res.scalars().all()
        if not ms:
            break

        texts = [
            (m.text or "") + ((" " + m.correction) if m.correction else "")
            for m in ms
        ]
        emb = await _embedder.embed(texts)
        # [NEW] shape guard: ensure 2D even when batch size == 1
        if getattr(emb, "ndim", 2) == 1:
            emb = emb.reshape(1, -1)
        items = [
            VSItem(
                ref_id=f"mistake:{m.id}",
                text=m.text or "",
                meta={"mistake_id": m.id, "tags": m.tags},
            )
            for m in ms
        ]
        await _maybe_await(_vstore.upsert(namespace, emb, items))

        total += len(ms)
        offset += len(ms)

    return {"ok": True, "namespace": namespace, "indexed": total, "dim": EMBED_DIM}


 # [NEW] Mistake 벡터 검색 + DB 매핑 API
 # - 히트의 ref_id("mistake:{id}")를 Mistake 레코드와 병합하여 바로 쓰기 좋은 형태로 반환
@app.post("/mistakes/search")
async def mistakes_search(
    q: str = Body(..., embed=True, description="검색 쿼리"),
    top_k: int = Body(5, embed=True),
    namespace: str = Body("mistakes", embed=True),
    db: AsyncSession = Depends(get_session),
):
    """
    벡터 검색 결과를 Mistake 레코드와 매칭해서 반환합니다.
    응답은 스키마 없이 단순 JSON으로 내려줍니다.
    """
    # (신규) 검색 결과와 실제 DB 레코드를 매칭해 메타데이터까지 한 번에 돌려주는 편의 API입니다.
    # 1) 쿼리 임베딩 → (1, dim) 2D 유지
    qemb = await _embedder.embed([q])  # (1, dim)
    # [NEW] shape guard: avoid faiss.normalize_L2 IndexError for 1D array
    if getattr(qemb, "ndim", 2) == 1:
        qemb = qemb.reshape(1, -1)
    hits = await _maybe_await(_vstore.query(namespace, qemb, top_k=top_k))

    # 2) ref_id에서 mistake:{id} 추출
    def _mid(ref: str | None):
        m = re.match(r"mistake:(\d+)$", str(ref or ""))
        return int(m.group(1)) if m else None

    ids = [_mid(h.get("ref_id")) for h in hits]
    ids = [i for i in ids if i is not None]
    if not ids:
        return {"ok": True, "hits": []}

    # 3) DB에서 해당 Mistake들 조회
    res = await db.execute(select(Mistake).where(Mistake.id.in_(ids)))
    rows = {m.id: m for m in res.scalars().all()}

    # 4) 원래 점수/순서를 유지하며 병합
    out = []
    for h in hits:
        mid = _mid(h.get("ref_id"))
        m = rows.get(mid)
        if not m:
            continue
        out.append({
            "score": float(h.get("score", 0.0)),
            "ref_id": h.get("ref_id"),
            "mistake": {
                "id": m.id,
                "text": m.text,
                "correction": m.correction,
                "tags": m.tags,
            },
        })
    return {"ok": True, "hits": out}
