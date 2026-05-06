# Local STT Mode (Qwen Only)

이 문서는 기존 코드를 수정/삭제하지 않고, 별도 엔트리포인트로 Qwen 로컬 STT를 사용하는 방법을 설명합니다.

## 1) 서버 실행

```bash
cd server
uv pip install -r requirements-local-stt.txt
./.venv/bin/python -m uvicorn app.main_local_stt:app --host 0.0.0.0 --port 8000
```

또는 루트에서:

```bash
./scripts/run_local_stt_server.sh
```

기본 안정 설정:

- `LOCAL_STT_ACTIVE_PROVIDER=qwen`
- `LOCAL_STT_QWEN_ISOLATE_PROCESS=1`
- `LOCAL_STT_QWEN_DEVICE_MAP=cpu`
- `LOCAL_STT_QWEN_DTYPE=float32`
- `LOCAL_STT_PRELOAD_ON_STARTUP=1`
- `LOCAL_STT_PRELOAD_PROVIDERS=qwen`
- `LOCAL_STT_PRELOAD_ON_SWITCH=1`
- `LOCAL_STT_FORCE_REALTIME_BUFFERED=1` (local mode에서 `/speech/realtime` OpenAI realtime 분기 강제 차단)
- `LOCAL_STT_REALTIME_NO_SPEECH_GRACE_MS=0`
- `LOCAL_STT_REALTIME_FINAL_TRANSCRIPT_TIMEOUT_MS=0`

기본적으로 `./scripts/run_local_stt_server.sh`는 이미 실행 중인 local STT 서버가 있으면
기존 프로세스를 재시작하여 최신 코드를 반영합니다.
재사용만 하려면:

```bash
RESTART_IF_RUNNING=0 ./scripts/run_local_stt_server.sh
```

`--reload` 필요 시:

```bash
ENABLE_RELOAD=1 ./scripts/run_local_stt_server.sh
```

## 2) Flutter 실행

```bash
flutter run -t lib/main_frontend_local_stt.dart --dart-define=ENGLISH_AI_SERVER_BASE_URL=http://127.0.0.1:8000
```

`/local_stt_switch` 화면에서 language만 설정해 테스트하면 됩니다. provider는 qwen 단일입니다.

## 3) 적용 범위

local STT 모드(`app.main_local_stt:app`)에서는 아래 STT 경로가 qwen 로컬 STT를 사용합니다.

- `/speech/turn` (Record/Speaking/Roleplay 등)
- `/speech/realtime` fallback transcribe (프리토킹 포함)

## 4) Qwen 모델 사전 다운로드(권장)

```bash
cd server
uv run python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(repo_id='Qwen/Qwen3-ASR-1.7B', local_dir='models/Qwen3-ASR-1.7B')
print('downloaded')
PY
```

```bash
export LOCAL_STT_QWEN_MODEL="/Users/jordi_k/Desktop/2026 University 7th Semester/english_ai/server/models/Qwen3-ASR-1.7B"
./scripts/run_local_stt_server.sh
```

## 5) 원래 동작으로 복귀

서버:

```bash
cd server
./.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Flutter:

```bash
flutter run -t lib/main_frontend.dart
```
