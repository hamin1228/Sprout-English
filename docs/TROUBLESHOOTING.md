# Sprout English — 트러블슈팅 가이드

---

## 1. Android 에뮬레이터에서 서버 연결이 안 됩니다

**증상**: 앱 실행 후 서버 요청이 모두 실패하거나 타임아웃이 발생합니다.

**원인**: Android 에뮬레이터는 `localhost`로 호스트 PC를 찾을 수 없습니다.

**해결**:
- 에뮬레이터에서는 `http://10.0.2.2:8000`을 사용해야 합니다.
- 앱의 **Settings** 화면 → 서버 주소를 `10.0.2.2:8000`으로 변경하세요.

| 환경 | 서버 주소 |
|------|-----------|
| Android 에뮬레이터 | `http://10.0.2.2:8000` |
| iOS 시뮬레이터 | `http://localhost:8000` |
| 실물 기기 (WiFi) | `http://[PC의 로컬 IP]:8000` |

PC의 로컬 IP 확인:
```bash
# macOS/Linux
ifconfig | grep "inet " | grep -v 127.0.0.1

# Windows
ipconfig
```

---

## 2. `OPENAI_API_KEY` 관련 오류

**증상**:
- `AuthenticationError: Incorrect API key provided`
- STT/TTS 기능이 동작하지 않음

**해결**:

```bash
# 1. server/.env 파일이 있는지 확인
ls server/.env

# 없으면 생성
cp server/.env.example server/.env

# 2. OPENAI_API_KEY 값 입력
# server/.env 파일을 열고 아래 줄 수정:
OPENAI_API_KEY=sk-proj-여기에_실제_키를_입력하세요
```

> API 키 발급: https://platform.openai.com/api-keys

---

## 3. MySQL 연결 실패

**증상**:
- `Connection refused (os error 111)`
- `Can't connect to MySQL server`
- FastAPI 서버 시작 시 DB 오류

**원인 및 해결**:

| 환경 | DB_HOST 설정 | 해결 방법 |
|------|-------------|-----------|
| Docker Compose | `mysql` | `server/.env`에 `DB_HOST=mysql` 설정 |
| 로컬 실행 | `127.0.0.1` | `server/.env`에 `DB_HOST=127.0.0.1` 설정 |

```bash
# Docker Compose 환경에서 MySQL 상태 확인
docker compose ps
docker compose logs mysql

# MySQL 컨테이너가 healthy 상태인지 확인
docker compose ps mysql
```

MySQL이 아직 초기화 중이면 FastAPI가 연결에 실패합니다. healthcheck가 통과될 때까지 기다리세요 (보통 10~30초).

---

## 4. Redis 연결 오류

**증상**:
- `redis.exceptions.ConnectionError: Error 111 connecting to localhost:6379`

**해결**:

```bash
# 로컬에서 Redis가 실행 중인지 확인
redis-cli ping   # PONG 이 출력되면 정상

# Redis 시작 (Homebrew)
brew services start redis

# Docker Compose 환경에서는 Redis 컨테이너가 자동 시작됨
docker compose ps redis
```

`server/.env`의 `REDIS_URL` 확인:
- 로컬: `REDIS_URL=redis://localhost:6379/0`
- Docker: `REDIS_URL=redis://redis:6379/0`

---

## 5. CORS 오류

**증상**:
- 브라우저 콘솔에 `CORS policy: No 'Access-Control-Allow-Origin' header`
- Flutter 웹에서 API 요청 실패

**해결**:

`server/.env` 파일에 `CORS_ORIGINS` 설정:

```env
# 개발 환경 (모든 Origin 허용)
CORS_ORIGINS=*

# 운영 환경 (특정 도메인만 허용)
CORS_ORIGINS=https://your-domain.com,https://app.your-domain.com
```

> **주의**: `CORS_ORIGINS=*` 상태에서는 쿠키/인증 헤더가 자동으로 비활성화됩니다.
> 운영 환경에서 인증이 필요하면 반드시 명시적 Origin을 설정하세요.

---

## 6. `docker compose up --build` 실패

**증상**: 빌드 또는 컨테이너 시작 실패

**체크리스트**:

```bash
# 1. .env 파일 세 개 모두 존재하는지 확인
ls .env server/.env vercel_api/.env

# 없으면 생성
cp .env.example .env
cp server/.env.example server/.env
cp vercel_api/.env.example vercel_api/.env

# 2. Docker Desktop이 실행 중인지 확인
docker --version
docker compose version

# 3. 포트 충돌 확인 (8000, 3000, 3306, 6379)
lsof -i :8000
lsof -i :3306

# 4. 로그 확인
docker compose logs backend
docker compose logs mysql
```

---

## 7. Flutter 빌드 오류

**증상**:
- `flutter run` 실패
- `pub get` 의존성 오류

**해결**:

```bash
# 의존성 재설치
flutter clean
flutter pub get

# 분석 오류 확인
flutter analyze

# Android SDK 경로 문제
flutter doctor
```

---

## 8. 음성 녹음이 안 됩니다 (마이크 권한)

**증상**: 녹음 버튼을 눌러도 반응이 없거나 권한 오류

**해결**:
- Android: 설정 → 앱 → Sprout English → 권한 → 마이크 허용
- iOS: 설정 → 개인정보 보호 → 마이크 → Sprout English 허용
- 에뮬레이터에서는 에뮬레이터 설정 → 마이크 입력 활성화 필요

---

## 9. TTS 음성이 재생되지 않습니다

**증상**: AI 응답 텍스트는 표시되지만 음성이 나오지 않음

**원인 및 해결**:

1. `OPENAI_TTS_MODEL`, `OPENAI_TTS_VOICE` 환경변수 확인
2. 에뮬레이터 볼륨 설정 확인
3. `just_audio` 패키지 권한 확인 (`audio_session` 설정)

```bash
# FastAPI TTS 엔드포인트 테스트
curl -X POST http://localhost:8000/tts/stream \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world", "voice": "nova"}' \
  --output test_audio.mp3
```

---

## 10. Next.js API (톤 변환) 오류

**증상**: 톤 변환 화면에서 오류 발생

**해결**:

```bash
# vercel_api/.env 확인
cat vercel_api/.env

# ANTHROPIC_API_KEY 입력 확인
# vercel_api/.env:
ANTHROPIC_API_KEY=sk-ant-여기에_실제_키를_입력하세요

# Next.js 서버 실행 확인
curl http://localhost:3000/api/health
```

---

## 로그 확인 방법

```bash
# FastAPI 로그 (Docker)
docker compose logs -f backend

# MySQL 로그
docker compose logs -f mysql

# 로컬 FastAPI 로그 레벨 변경
# server/.env:
LOG_LEVEL=DEBUG
```

---

## 추가 도움이 필요한 경우

이슈를 [GitHub Issues](https://github.com/hamin1228/Sprout-English/issues)에 등록하거나, 아래 정보를 포함해 팀원에게 문의하세요:

1. 운영체제 및 버전
2. Flutter SDK 버전 (`flutter --version`)
3. Python 버전 (`python3 --version`)
4. Docker 버전 (`docker --version`)
5. 오류 메시지 전문
6. `docker compose logs backend` 출력 내용
