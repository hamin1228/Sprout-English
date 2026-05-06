# Sprout English

> AI 기반 개인화 영어 말하기 · 쓰기 학습 모바일 앱

---

## 프로젝트 소개

Sprout English는 혼자서도 실전 영어 실력을 키울 수 있도록 AI가 1:1 코치 역할을 해주는 모바일 학습 애플리케이션입니다.

음성 녹음을 통해 영어로 말하는 연습을 하면 AI가 발음·유창성·표현을 분석해 즉각적인 피드백을 제공합니다.
실제 상황(카페 주문, 길 묻기, 회의 일정 조율 등)을 기반으로 한 역할극 학습을 통해 다양한 회화 상황을 반복 연습할 수 있습니다.

> 2026 남서울대학교 지능정보통신공학과 졸업작품전시회 출품작

---

## 주요 기능

- **AI 프리토킹** — 실시간 음성 대화, AI가 자연스러운 대화 상대로 응답
- **AI 튜터 채팅** — 텍스트 기반 영어 대화 및 표현 교정
- **롤플레이** — 카페·공항·회의 등 실제 상황 역할극 시나리오 학습
- **스피킹 평가** — 발음·WPM·침묵 비율·유창성 점수 자동 분석
- **문법 검사 / 글쓰기 교정** — GPT 기반 실시간 교정 및 diff 피드백
- **TOEIC 라이팅** — TOEIC Writing 유형별 문제 풀이 및 채점
- **단어 학습 (SRS)** — SM-2 알고리즘 기반 간격 반복 복습 시스템
- **오늘의 표현** — 매일 새로운 영어 표현 학습
- **학습 통계** — 연속 학습일, 세션 수, 점수 추이 시각화

---

## 기술 스택

### Frontend
- Flutter 3.41 (Dart SDK ^3.9.2)
- flutter_riverpod — 상태 관리
- go_router — 화면 라우팅
- dio — HTTP 통신
- web_socket_channel — 실시간 WebSocket
- record / just_audio — 음성 녹음 및 재생

### Backend
- FastAPI + Uvicorn (Python)
- OpenAI GPT-5-nano — 대화 생성 / 문법 교정 / 채점
- OpenAI TTS API (gpt-4o-mini-tts) — 음성 합성
- OpenAI Whisper API — 음성 인식 (STT)
- Qwen3-ASR-1.7B — 로컬 온디바이스 STT (선택)
- LangChain — AI 체인 구성
- SQLAlchemy + MySQL — 학습 데이터 저장
- Redis + RQ — 캐시 및 작업 큐
- WebSocket — 실시간 스트리밍

---

## 프로젝트 구조

```
english_ai/
├── lib/                        # Flutter 앱 소스
│   ├── core/                   # 네트워크, 오디오, 설정, 통계 공통 모듈
│   ├── feature/                # 기능별 페이지 (롤플레이, 단어, 글쓰기 등)
│   ├── screens/                # 주요 화면 위젯
│   ├── widgets/                # 공통 위젯
│   └── main.dart
├── server/                     # FastAPI 백엔드
│   ├── app/
│   │   ├── services/           # GPT, STT, TTS, SRS 서비스 로직
│   │   ├── routers/            # API 라우터
│   │   ├── models.py           # DB 모델 (SQLAlchemy)
│   │   ├── ws.py               # WebSocket 핸들러
│   │   ├── tts.py              # TTS 스트리밍
│   │   └── stt_pipeline.py     # STT 파이프라인
│   ├── requirements.txt
│   └── .env.example
├── assets/                     # 롤플레이 배경 이미지 등 앱 리소스
├── docs/                       # 문서 및 스크린샷
│   └── screenshots/
└── README.md
```

---

## 실행 방법

### 방법 A — Docker (추천, 서버 환경)

> **사전 준비:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치

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
| `.env` | docker-compose.yml의 MySQL 컨테이너 생성에 사용 |
| `server/.env` | FastAPI 서버 환경 변수 (OpenAI API Key, DB 접속 정보) |
| `vercel_api/.env` | Next.js API 환경 변수 (Anthropic API Key) |

> 실제 `.env` 파일들은 `.gitignore`에 등록되어 있어 GitHub에 올라가지 않습니다. `.env.example` 파일만 커밋하세요.

각 파일에서 아래 값을 채워주세요:

`.env`
```env
MYSQL_ROOT_PASSWORD=your_root_password
DB_NAME=english_ai
DB_USER=ea
DB_PASSWORD=your_db_password
```

`server/.env`
```env
DB_PASSWORD=your_db_password
OPENAI_API_KEY=sk-proj-...
```

`vercel_api/.env`
```env
ANTHROPIC_API_KEY=sk-ant-...
```

#### 3. 전체 서비스 실행

```bash
docker compose up --build
```

#### 4. 접속 주소

| 서비스 | 주소 | 역할 |
|--------|------|------|
| FastAPI 백엔드 | http://localhost:8000 | STT / TTS / 대화 / 채점 |
| Next.js API | http://localhost:3000 | 톤 변환 (Claude API) |
| MySQL | localhost:3306 | 학습 데이터 DB |
| Redis | localhost:6379 | 캐시 / 작업 큐 |

#### 5. 종료

```bash
# 전체 종료
docker compose down

# DB 데이터까지 완전 삭제 (초기화)
docker compose down -v
```

#### 유용한 명령어

```bash
# 백그라운드 실행
docker compose up -d --build

# 서비스별 로그 확인
docker compose logs -f backend
docker compose logs -f vercel-api

# 특정 서비스만 재시작
docker compose restart backend
```

---

### 방법 B — 로컬 직접 실행 (Flutter 앱 개발 시)

**사전 준비:** Flutter SDK 3.41+, Python 3.10+, Node.js 20+, MySQL, Android Studio

#### 1. 저장소 클론

```bash
git clone https://github.com/hamin1228/Sprout-English.git
cd Sprout-English
```

#### 2. FastAPI 백엔드 실행

```bash
cd server
cp .env.example .env    # OPENAI_API_KEY, DB 정보 입력
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

#### 3. Next.js API 서버 실행

```bash
cd vercel_api
cp .env.example .env    # ANTHROPIC_API_KEY 입력
npm install
npm run dev             # http://localhost:3000
```

#### 4. Flutter 앱 실행

```bash
cd ..
flutter pub get
flutter run
```

> Android 에뮬레이터 사용 시 서버 주소가 자동으로 `http://10.0.2.2:8000` 으로 설정됩니다.
> 실물 기기 사용 시 앱 Settings 화면에서 서버 IP를 직접 입력하세요.

---

## GitHub에 올리면 안 되는 파일

```
server/.env           # DB 비밀번호, OpenAI API Key
vercel_api/.env       # Anthropic API Key
```

`.gitignore`에 이미 등록되어 있습니다. `.env.example` 파일만 올리세요.

---

## 환경 변수

`server/.env.example` 파일을 복사해 `server/.env`로 만든 후 아래 값을 채워주세요.

```env
DB_USER=your_db_user
DB_PASSWORD=your_db_password
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=english_ai

OPENAI_API_KEY=sk-proj-your_openai_api_key_here
```

---

## 화면 예시

> `docs/screenshots/` 폴더에 스크린샷을 추가해주세요.

---

## 시스템 구조

```
[Android 앱 (Flutter)]
        │  HTTP / WebSocket
        ▼
[FastAPI 서버]
  ├─ WebSocket → GPT-5-nano (대화 스트리밍)
  ├─ POST /stt → Whisper / Qwen3-ASR (음성 인식)
  ├─ POST /tts → OpenAI TTS (음성 합성)
  └─ REST API → MySQL (학습 기록 / 점수 저장)
```

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

## 라이선스

This project is licensed under the MIT License.
