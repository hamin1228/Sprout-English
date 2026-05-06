# Sprout English — 시스템 아키텍처

## 전체 구조

```
┌──────────────────────────────────────────────────────────────────────┐
│                     모바일 앱 (Flutter)                               │
│                   Android / iOS                                       │
│                                                                       │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │ AI 프리토킹│  │ AI 튜터채팅│  │ 롤플레이     │  │ 스피킹 평가 │  │
│  └────────────┘  └────────────┘  └──────────────┘  └─────────────┘  │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │ 글쓰기교정 │  │ TOEIC Writ │  │ SRS 단어복습 │  │ 학습 통계   │  │
│  └────────────┘  └────────────┘  └──────────────┘  └─────────────┘  │
└────────────────────────────┬─────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │ HTTP/REST                   │ WebSocket
              ▼                             ▼
┌─────────────────────────────────────────────────────────┐
│               FastAPI 서버 (port 8000)                  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │                 app/main.py                      │   │
│  │  - 엔드포인트 등록                                │   │
│  │  - CORS 미들웨어 (CORS_ORIGINS 환경변수 기반)    │   │
│  │  - trace_id 미들웨어 (요청 추적)                 │   │
│  │  - rate limiting (슬라이딩 윈도우)               │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌───────────┐  │
│  │ STT      │ │ TTS      │ │ WebSocket│ │ REST API  │  │
│  │ /speech/ │ │ /tts/    │ │ /ws/chat │ │ /vocab/   │  │
│  │ turn     │ │ stream   │ │ stream   │ │ /writing/ │  │
│  └──────┬───┘ └────┬─────┘ └────┬────┘ └─────┬─────┘  │
│         │          │            │             │         │
│         └──────────┴────────────┴─────────────┘         │
│                         │                               │
│                 ┌───────┴────────┐                      │
│                 │  서비스 레이어  │                      │
│                 │                │                      │
│                 │ - stt.py       │                      │
│                 │ - llm.py       │                      │
│                 │ - scoring.py   │                      │
│                 │ - srs.py       │                      │
│                 │ - roleplay.py  │                      │
│                 └───────┬────────┘                      │
└─────────────────────────┼───────────────────────────────┘
                          │
         ┌────────────────┼─────────────────┐
         │                │                 │
         ▼                ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌─────────────────┐
│  MySQL 8.4   │  │  Redis 7     │  │  OpenAI API     │
│  (port 3306) │  │  (port 6379) │  │                 │
│              │  │              │  │  - GPT-4o-mini  │
│  - 학습 기록  │  │  - 캐시      │  │  - Whisper STT  │
│  - 스피킹 점수│  │  - 작업 큐   │  │  - TTS          │
│  - 단어장    │  │              │  │                 │
│  - SRS 상태  │  │              │  │                 │
└──────────────┘  └──────────────┘  └─────────────────┘

┌─────────────────────────────────────────────────────────┐
│               Next.js API 서버 (port 3000)              │
│  POST /api/paraphrase ──▶ Anthropic Claude API         │
│  (톤 변환 / 문장 패러프레이즈)                           │
└─────────────────────────────────────────────────────────┘
```

---

## 음성 처리 흐름 (STT → GPT → TTS)

```
사용자 음성 녹음 (Flutter record 패키지)
           │
           │ WAV 파일 POST /speech/turn
           ▼
  [FastAPI] 파일 검증
  - 크기 ≤ 10MB
  - 길이 ≤ 60초 (WAV 헤더 파싱)
  - MIME 타입 검증
           │
           ▼
  [OpenAI Whisper API]
  음성 → 텍스트 전사 (STT)
           │
           ▼
  [GPT-4o-mini] 대화 생성
  - 시스템 프롬프트 (상황별)
  - 이전 대화 컨텍스트 유지
           │
           ▼
  [OpenAI TTS API] (gpt-4o-mini-tts)
  텍스트 → 음성 합성
           │
           │ 오디오 스트림 응답
           ▼
  [Flutter just_audio]
  AI 응답 음성 재생
```

---

## WebSocket 실시간 대화 흐름

```
Flutter ──── WS connect ────▶ FastAPI /ws/chat/stream
       ◀─── session_id ──────
       ──── {text: "..."} ──▶ GPT-4o-mini (스트리밍)
       ◀─── delta chunks ───  실시간 텍스트 스트리밍
       ◀─── [done] ─────────  대화 완료 신호
```

---

## SRS (간격 반복) 알고리즘

SM-2 알고리즘 기반으로 단어 복습 간격을 자동 조정합니다.

```
복습 결과 (0~5 점수)
       │
       ▼
SM-2 계산
  - easiness_factor (EF) 업데이트
  - 복습 간격(interval) 계산
  - 다음 복습 날짜 결정
       │
       ▼
MySQL VocabSRSState 업데이트
       │
       ▼
다음 복습 큐 생성
```

---

## DB 스키마 (주요 테이블)

| 테이블 | 설명 |
|--------|------|
| `mistakes` | 사용자 영어 실수 기록 |
| `srs_state` | 문장/표현 SRS 상태 (SM-2) |
| `vocab_card` | 단어장 |
| `vocab_srs_state` | 단어 SRS 상태 |
| `speaking_score` | 스피킹 평가 결과 |

---

## 디렉토리별 역할

### Flutter (`lib/`)

| 디렉토리 | 역할 |
|----------|------|
| `core/audio/` | `record` 패키지로 녹음, `just_audio`로 재생 |
| `core/network/` | `dio` 기반 HTTP 클라이언트, 서버 URL 관리 |
| `core/settings/` | 서버 IP 등 사용자 설정 영속화 |
| `core/statistics/` | 학습 통계 집계 및 로컬 저장 |
| `feature/free_talk/` | WebSocket push-to-talk 실시간 대화 |
| `feature/roleplay/` | 역할극 시나리오 선택 → 대화 → 결과 |
| `feature/speaking/` | 스피킹 평가 및 점수 시각화 |
| `feature/writing/` | 글쓰기 교정 diff + TOEIC Writing |
| `feature/vocab/` | SRS 단어 복습 카드 |
| `screens/` | 홈, 채팅, 프로필, 설정 등 주요 화면 |

### FastAPI (`server/app/`)

| 파일/디렉토리 | 역할 |
|--------------|------|
| `main.py` | 엔트리포인트, 미들웨어, 라우터 등록 |
| `config_loader.py` | `pydantic_settings` 기반 환경변수 로딩 |
| `models.py` | SQLAlchemy ORM 모델 |
| `schemas.py` | Pydantic 요청/응답 스키마 |
| `db.py` | async MySQL 세션 (`asyncmy` 드라이버) |
| `ws.py` | WebSocket 대화 상태 관리 |
| `tts.py` | TTS 스트리밍 라우터 |
| `stt_pipeline.py` | STT 파이프라인 (Whisper / 로컬 STT) |
| `services/srs.py` | SM-2 SRS 알고리즘 |
| `services/scoring.py` | 스피킹 점수 계산 |
| `services/roleplay.py` | 역할극 시나리오 생성 |
| `rate_limit.py` | 슬라이딩 윈도우 레이트 리미터 |
