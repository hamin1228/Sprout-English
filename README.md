# Sprout English 🌱

> AI 기반 개인화 영어 말하기 · 쓰기 학습 모바일 앱

[![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.117-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![Python](https://img.shields.io/badge/Python-3.10-3776AB?logo=python)](https://python.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 2026 남서울대학교 지능정보통신공학과 졸업작품전시회 출품작

---

## 프로젝트 개요

Sprout English는 AI가 1:1 코치 역할을 수행하는 모바일 영어 학습 앱입니다.

음성 녹음으로 말하기 연습을 하면 OpenAI Whisper가 전사(STT)하고, GPT가 발음·유창성·표현을 분석해 즉각 피드백을 제공합니다. 텍스트 교정, 역할극, TOEIC Writing, SRS 단어 복습까지 영어 학습에 필요한 핵심 기능을 하나의 앱에 통합했습니다.

### 주요 특징

- 실시간 AI 음성 대화 (WebSocket 스트리밍)
- OpenAI Whisper STT + TTS 파이프라인
- SM-2 알고리즘 기반 단어 복습 (SRS)
- FastAPI + Flutter 풀스택 아키텍처
- Docker Compose 원클릭 서버 실행

---

## 주요 기능

| 기능 | 설명 |
|------|------|
| **AI 프리토킹** | 실시간 음성 대화 — WebSocket 스트리밍으로 AI와 자연스러운 영어 회화 |
| **AI 튜터 채팅** | 텍스트 기반 영어 대화, 표현 교정, 예문 제공 |
| **롤플레이** | 카페·공항·회의 등 실제 상황 역할극 시나리오 반복 연습 |
| **스피킹 평가** | 발음·WPM·침묵 비율·유창성 점수 자동 분석 및 시각화 |
| **문법/글쓰기 교정** | GPT 기반 실시간 교정 및 변경점 diff 피드백 |
| **TOEIC Writing** | TOEIC Writing 유형별 문제 풀이 및 AI 채점 |
| **SRS 단어 복습** | SM-2 알고리즘 기반 간격 반복 복습 시스템 |
| **오늘의 표현** | 매일 새로운 영어 표현 학습 |
| **학습 통계** | 연속 학습일, 세션 수, 점수 추이 시각화 |

---

## 기술 스택

### Frontend
| 기술 | 용도 |
|------|------|
| Flutter 3.41 (Dart ^3.9.2) | 크로스플랫폼 모바일 앱 |
| flutter_riverpod | 상태 관리 |
| go_router | 선언형 화면 라우팅 |
| dio | HTTP 통신 |
| web_socket_channel | 실시간 WebSocket |
| record / just_audio | 음성 녹음 및 재생 |

### Backend
| 기술 | 용도 |
|------|------|
| FastAPI + Uvicorn (Python 3.10) | REST API + WebSocket 서버 |
| OpenAI GPT-4o-mini | 대화 생성 / 문법 교정 / 채점 |
| OpenAI TTS (gpt-4o-mini-tts) | 음성 합성 |
| OpenAI Whisper | 음성 인식 (STT) |
| LangChain | AI 체인 구성 |
| SQLAlchemy (async) + MySQL 8.4 | 학습 데이터 저장 |
| Redis 7 + RQ | 캐시 및 작업 큐 |
| WebSocket | 실시간 AI 스트리밍 |

### Infra
| 기술 | 용도 |
|------|------|
| Docker + Docker Compose | 서버 환경 컨테이너화 |
| Next.js (Node 20) | Claude API 연동 톤 변환 서비스 |
| MySQL 8.4 | 관계형 데이터베이스 |
| Redis 7-alpine | 캐시 / 작업 큐 |

---

## 시스템 아키텍처

```
┌─────────────────────────────────────────┐
│          Android / iOS 앱               │
│              (Flutter)                  │
└──────────┬──────────────┬───────────────┘
           │ HTTP/REST    │ WebSocket
           ▼              ▼
┌─────────────────────────────────────────┐
│           FastAPI 서버 (8000)           │
│                                         │
│  POST /speech/turn  ──▶ Whisper STT    │
│  POST /tts          ──▶ OpenAI TTS     │
│  WS   /ws/chat      ──▶ GPT 스트리밍  │
│  POST /writing/…    ──▶ GPT 교정       │
│  REST /vocab/…      ──▶ SRS 복습       │
│  REST /roleplay/…   ──▶ 역할극 생성   │
│  GET  /healthz      ──▶ 헬스체크       │
└──────┬──────────────────────────────────┘
       │
       ├──▶ MySQL 8.4 (학습 기록 / 점수 / 단어)
       ├──▶ Redis 7   (캐시 / 작업 큐)
       └──▶ OpenAI API (GPT / Whisper / TTS)

┌─────────────────────────────────────────┐
│       Next.js API 서버 (3000)           │
│  POST /api/paraphrase ──▶ Claude API   │
│  (톤 변환 / 패러프레이즈)               │
└─────────────────────────────────────────┘
```

---

## 폴더 구조

```
Sprout-English/
├── lib/                          # Flutter 앱 소스
│   ├── main.dart                 # 앱 엔트리포인트 (SproutEnglishApp)
│   ├── app.dart                  # Riverpod + go_router 기반 앱
│   ├── router.dart               # 라우팅 설정
│   ├── config/                   # API 엔드포인트 설정
│   ├── core/
│   │   ├── audio/                # 음성 녹음/재생 컨트롤러
│   │   ├── network/              # HTTP 클라이언트, 서버 URL 설정
│   │   ├── profile/              # 사용자 프로필
│   │   ├── settings/             # 앱 설정 (서버 IP 등)
│   │   ├── statistics/           # 학습 통계 집계
│   │   └── theme/                # 공통 테마
│   ├── feature/                  # 기능별 페이지
│   │   ├── free_talk/            # AI 프리토킹
│   │   ├── roleplay/             # 롤플레이
│   │   ├── speaking/             # 스피킹 평가
│   │   ├── writing/              # 글쓰기 교정 / TOEIC Writing
│   │   ├── vocab/                # 단어 학습
│   │   ├── drill/                # 패턴 드릴
│   │   └── paraphrase/           # 톤 변환
│   ├── screens/                  # 주요 화면 위젯
│   └── widgets/                  # 공통 위젯
│
├── server/                       # FastAPI 백엔드
│   ├── app/
│   │   ├── main.py               # FastAPI 엔트리포인트
│   │   ├── config_loader.py      # 환경변수 / 설정
│   │   ├── models.py             # DB 모델 (SQLAlchemy ORM)
│   │   ├── schemas.py            # Pydantic 스키마
│   │   ├── db.py                 # DB 세션 관리
│   │   ├── ws.py                 # WebSocket 핸들러
│   │   ├── tts.py                # TTS 라우터
│   │   ├── stt_pipeline.py       # STT 파이프라인
│   │   ├── routers/
│   │   │   ├── speaking.py       # 스피킹 평가 라우터
│   │   │   └── writing.py        # 글쓰기 교정 라우터
│   │   └── services/
│   │       ├── stt.py            # STT 서비스
│   │       ├── llm.py            # LLM 서비스
│   │       ├── scoring.py        # 발음/유창성 채점
│   │       ├── srs.py            # SRS (간격 반복) 알고리즘
│   │       ├── vocab_srs.py      # 단어 SRS
│   │       └── roleplay.py       # 역할극 생성
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .env.example
│
├── vercel_api/                   # Next.js API (Claude 톤 변환)
│   ├── Dockerfile
│   └── .env.example
│
├── assets/
│   ├── roleplay/                 # 역할극 배경 이미지 및 카탈로그
│   └── toeic_writing_images/     # TOEIC Writing 이미지
│
├── docs/                         # 문서
│   ├── ARCHITECTURE.md
│   ├── TROUBLESHOOTING.md
│   └── screenshots/              # 스크린샷 가이드
│
├── docker-compose.yml
├── .env.example                  # Docker Compose MySQL 환경변수
└── README.md
```

---

## 스크린샷

> 스크린샷 촬영 가이드는 [docs/screenshots/README.md](docs/screenshots/README.md) 를 참고하세요.

---

## 실행 방법

### 방법 A — Docker (서버 백엔드 실행)

> **사전 준비:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치 필요

#### 1. 저장소 클론

```bash
git clone https://github.com/hamin1228/Sprout-English.git
cd Sprout-English
```

#### 2. 환경 변수 파일 생성

```bash
cp .env.example .env
cp server/.env.example server/.env
cp vercel_api/.env.example vercel_api/.env
```

| 파일 | 용도 |
|------|------|
| `.env` | Docker Compose MySQL 컨테이너 설정 |
| `server/.env` | FastAPI 서버 환경변수 (OpenAI Key, DB 접속 정보 등) |
| `vercel_api/.env` | Next.js API 환경변수 (Anthropic API Key) |

각 `.env` 파일을 열어 실제 값을 입력하세요 (아래 **환경변수 설정** 섹션 참고).

#### 3. 빌드 및 실행

```bash
docker compose up --build
```

#### 4. 접속 주소

| 서비스 | 주소 | 설명 |
|--------|------|------|
| FastAPI 백엔드 | http://localhost:8000 | STT / TTS / 대화 / 채점 |
| API 문서 (Swagger) | http://localhost:8000/docs | 자동 생성 API 문서 |
| Next.js API | http://localhost:3000 | 톤 변환 (Claude API) |
| MySQL | localhost:3306 | 학습 데이터 DB |
| Redis | localhost:6379 | 캐시 / 작업 큐 |

#### 유용한 명령어

```bash
# 백그라운드 실행
docker compose up -d --build

# 서비스별 로그 확인
docker compose logs -f backend
docker compose logs -f vercel-api

# 서비스 재시작
docker compose restart backend

# 전체 종료
docker compose down

# DB 데이터까지 완전 삭제
docker compose down -v
```

---

### 방법 B — 로컬 직접 실행 (Flutter 앱 개발 시)

**사전 준비:** Flutter SDK 3.41+, Python 3.10+, Node.js 20+, MySQL 8+, Redis, Android Studio

#### 1. 저장소 클론

```bash
git clone https://github.com/hamin1228/Sprout-English.git
cd Sprout-English
```

#### 2. FastAPI 백엔드 실행

```bash
cd server
cp .env.example .env          # OPENAI_API_KEY 등 실제 값 입력
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

#### 3. Next.js API 서버 실행 (선택)

```bash
cd ../vercel_api
cp .env.example .env          # ANTHROPIC_API_KEY 입력
npm install
npm run dev                   # http://localhost:3000
```

#### 4. Flutter 앱 실행

```bash
cd ..
flutter pub get
flutter run
```

#### Android Emulator에서 API 주소 설정

Android 에뮬레이터는 `localhost`로 호스트를 찾을 수 없습니다.

| 환경 | 서버 주소 |
|------|-----------|
| Android 에뮬레이터 | `http://10.0.2.2:8000` (자동 설정) |
| 실물 기기 | 앱 Settings 화면에서 서버 IP 직접 입력 |
| iOS 시뮬레이터 | `http://localhost:8000` |

---

## 환경변수 설정

### server/.env 주요 항목

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `OPENAI_API_KEY` | OpenAI API 키 (필수) | — |
| `DB_HOST` | MySQL 호스트 | `127.0.0.1` |
| `DB_PASSWORD` | MySQL 비밀번호 | — |
| `REDIS_URL` | Redis 연결 URL | `redis://localhost:6379/0` |
| `OPENAI_CHAT_MODEL` | GPT 모델명 | `gpt-4o-mini` |
| `OPENAI_TTS_MODEL` | TTS 모델명 | `gpt-4o-mini-tts` |
| `OPENAI_TTS_VOICE` | TTS 음성 | `nova` |
| `CORS_ORIGINS` | 허용 Origin (쉼표 구분) | `*` |
| `APP_ENV` | 실행 환경 | `development` |
| `LOG_LEVEL` | 로그 레벨 | `INFO` |

> 전체 항목은 [`server/.env.example`](server/.env.example) 참고

---

## 테스트 실행

### Flutter 테스트

```bash
# 정적 분석
flutter analyze

# 전체 테스트
flutter test

# 특정 테스트
flutter test test/widget_test.dart
```

### FastAPI 테스트

```bash
cd server
pip install -r requirements.txt
pytest tests/ -v
```

> 현재 FastAPI 테스트는 외부 API(OpenAI, MySQL, Redis)를 실제로 호출하지 않는 mock 기반으로 구성 예정입니다.

---

## 보안 주의사항

- `server/.env`, `vercel_api/.env`, `.env` 파일은 **절대 Git에 커밋하지 마세요**. `.gitignore`에 등록되어 있습니다.
- 운영 환경에서는 `CORS_ORIGINS=*` 대신 허용할 도메인을 명시적으로 지정하세요.
  ```env
  CORS_ORIGINS=https://your-domain.com,https://app.your-domain.com
  ```
- `CORS_ORIGINS=*` 상태에서는 `allow_credentials=False`로 자동 설정됩니다 (브라우저 정책 준수).
- OpenAI API 키가 노출된 경우 즉시 [platform.openai.com/api-keys](https://platform.openai.com/api-keys) 에서 폐기하세요.
- Docker 컨테이너는 non-root 사용자(`appuser`)로 실행됩니다.

---

## 배포 / 시연 시 주의사항

- MySQL 초기 스키마는 앱 첫 실행 시 SQLAlchemy `create_all()`로 자동 생성됩니다.
- `docker compose up` 실행 전 반드시 세 개의 `.env` 파일이 모두 존재해야 합니다.
- Flutter 앱 실행 시 Settings 화면에서 서버 IP를 실제 서버 주소로 변경하세요.
- `OPENAI_API_KEY` 없이 실행하면 STT/TTS/GPT 기능이 개발용 stub으로 동작합니다.

---

## 개발 현황

### 완료
- [x] JWT 기반 사용자 인증 (회원가입 / 로그인 / 토큰 갱신 / 로그아웃)
- [x] FastAPI 모듈 분리 (main.py → core/ + routers/ 구조 리팩토링)
- [x] CI/CD 파이프라인 (GitHub Actions) 구성
- [x] Flutter 인증 UI 및 Riverpod 기반 인증 상태 관리
- [x] AI 프리토킹 (WebSocket 실시간 스트리밍)
- [x] 스피킹 평가 (WPM / 침묵 비율 / 유창성 채점)
- [x] 글쓰기 교정 및 TOEIC Writing
- [x] SRS 단어 복습 (SM-2 알고리즘)
- [x] 롤플레이 시나리오 (카페 / 공항 / 회의)
- [x] 학습 통계 및 진도 시각화
- [x] Docker Compose 원클릭 배포 환경

### 진행 중
- [ ] 401 응답 시 refresh_token 자동 재시도 로직
- [ ] 톤 변환(Paraphrase) UI 렌더링 완성
- [ ] 패턴 드릴 화면 구현

### 향후 계획
- [ ] Qwen3-ASR-1.7B 온디바이스 STT 통합
- [ ] iOS 빌드 및 TestFlight 배포
- [ ] Redis token blacklist (로그아웃 서버 측 무효화)
- [ ] 학습 데이터 시각화 대시보드 고도화

---

## 내가 이 프로젝트에서 구현한 핵심 내용 (여하민 / Frontend)

- Flutter + Riverpod 기반 전체 UI 설계 및 구현
- go_router 기반 선언형 네비게이션 아키텍처 구성
- **JWT 인증 플로우 완성**: 회원가입 · 로그인 화면, flutter_secure_storage 토큰 저장, 앱 시작 시 `/auth/me` 검증 → 자동 라우팅
- WebSocket 실시간 AI 대화 화면 (push-to-talk + 스트리밍 응답)
- 스피킹 평가 결과 시각화 (WPM, 침묵 비율, 유창성 점수 카드)
- SM-2 SRS 단어 복습 UI 플로우 구현
- 역할극 시나리오 선택 → 대화 → 결과 전체 플로우
- TOEIC Writing 문제 화면 및 AI 채점 결과 표시
- `record` + `just_audio` 패키지 통합으로 음성 녹음 / 재생 파이프라인 구현
- Android Emulator / 실물 기기 서버 IP 동적 설정 기능
- 학습 통계 대시보드 (연속 학습일, 세션 점수 추이, 활동 기록 시각화)

---

## 트러블슈팅

자세한 내용은 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 참고

| 문제 | 원인 | 해결 |
|------|------|------|
| Android에서 서버 연결 안 됨 | `localhost` 주소 사용 | Settings에서 `10.0.2.2:8000` 입력 |
| `OPENAI_API_KEY` 오류 | .env 파일 누락 | `cp server/.env.example server/.env` 후 키 입력 |
| MySQL 연결 실패 | DB_HOST 설정 오류 | Docker: `mysql`, 로컬: `127.0.0.1` |
| CORS 오류 | Origin 허용 미설정 | `CORS_ORIGINS` 환경변수 확인 |
| `docker compose` 실패 | .env 파일 없음 | 세 개 `.env` 파일 모두 생성 확인 |

---

## 팀원

| 이름 | 역할 |
|------|------|
| 강민서 | Backend / AI |
| 여인준 | Backend / AI |
| 여하민 | Frontend / Flutter |

지도교수: 정영화 교수님

---

## 개발 기간

2025.09 ~ 2026.06

---

## GitHub 저장소 설정 (관리자용)

아래 명령어로 저장소 설명과 topic을 설정할 수 있습니다:

```bash
gh repo edit hamin1228/Sprout-English \
  --description "AI-powered English speaking and writing learning app built with Flutter, FastAPI, OpenAI, MySQL, and Redis." \
  --add-topic flutter \
  --add-topic fastapi \
  --add-topic openai \
  --add-topic english-learning \
  --add-topic ai-tutor \
  --add-topic speech-to-text \
  --add-topic text-to-speech \
  --add-topic mysql \
  --add-topic redis \
  --add-topic docker \
  --add-topic graduation-project
```

---

## 회원가입 / 로그인 기능

### 새 백엔드 API

| Method | Endpoint | 설명 | 인증 필요 |
|--------|----------|------|-----------|
| POST | `/auth/signup` | 이메일/비밀번호 회원가입 | ❌ |
| POST | `/auth/login` | 로그인 → access/refresh token 발급 | ❌ |
| GET | `/auth/me` | 현재 로그인 유저 정보 조회 | ✅ Bearer |
| POST | `/auth/refresh` | refresh_token → 새 access_token 발급 | ❌ |
| POST | `/auth/logout` | 서버 응답 `{ok: true}` (클라이언트 토큰 삭제) | ✅ Bearer |

### 새 환경변수 (`server/.env`)

```env
JWT_SECRET_KEY=your-strong-random-secret   # 운영 환경에서 반드시 변경
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=14
```

### curl 테스트 예시

```bash
# 회원가입
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","nickname":"test"}'

# 로그인
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# 내 정보 조회 (ACCESS_TOKEN은 로그인 응답의 access_token)
curl http://localhost:8000/auth/me \
  -H "Authorization: Bearer <ACCESS_TOKEN>"

# 토큰 재발급
curl -X POST http://localhost:8000/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"<REFRESH_TOKEN>"}'
```

### Flutter 실행 방법

```bash
# iPhone 실기기에서 Mac 로컬 서버에 연결
flutter run --dart-define=ENGLISH_AI_SERVER_BASE_URL=http://<맥북Wi-FiIP>:8000

# 예시
flutter run --dart-define=ENGLISH_AI_SERVER_BASE_URL=http://192.168.0.12:8000
```

> ⚠️ **iPhone 실기기 주의**: `localhost` / `127.0.0.1`은 iPhone 자기 자신을 의미합니다.  
> Mac 서버에 접속하려면 반드시 Mac의 Wi-Fi IP를 사용해야 합니다.  
> 앱 설정 화면에서 서버 주소를 런타임으로 변경하는 것도 가능합니다(재빌드 불필요).

### 앱 인증 흐름

1. 앱 실행 → secure storage에 access_token 확인
2. 토큰 있음 → `/auth/me` 호출 → 성공 시 홈 화면 이동
3. 토큰 없음 / 만료 → 로그인 화면 표시
4. 로그아웃 → Settings 탭 → 로그아웃 버튼 → 로컬 토큰 삭제 → 로그인 화면

### 로그아웃 방식

JWT stateless 방식이므로 서버는 `{ok: true}`만 반환합니다.  
Flutter 클라이언트에서 `flutter_secure_storage` 토큰을 삭제하는 방식으로 로그아웃합니다.  
추후 Redis token blacklist 방식으로 서버 측 무효화 확장 가능합니다.

---

## 라이선스

This project is licensed under the [MIT License](LICENSE).
