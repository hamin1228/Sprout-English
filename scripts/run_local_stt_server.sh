#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"
PYTHON_BIN="$SERVER_DIR/.venv/bin/python"
PORT="${PORT:-8000}"
ENABLE_RELOAD="${ENABLE_RELOAD:-0}"
RESTART_IF_RUNNING="${RESTART_IF_RUNNING:-1}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "python not found: $PYTHON_BIN" >&2
  echo "Run: cd \"$SERVER_DIR\" && uv venv && uv pip install -r requirements-local-stt.txt" >&2
  exit 1
fi

cd "$SERVER_DIR"
export LOCAL_STT_ACTIVE_PROVIDER="${LOCAL_STT_ACTIVE_PROVIDER:-qwen}"
export LOCAL_STT_QWEN_ISOLATE_PROCESS="${LOCAL_STT_QWEN_ISOLATE_PROCESS:-1}"
export LOCAL_STT_QWEN_DEVICE_MAP="${LOCAL_STT_QWEN_DEVICE_MAP:-cpu}"
export LOCAL_STT_QWEN_DTYPE="${LOCAL_STT_QWEN_DTYPE:-float32}"
export LOCAL_STT_PRELOAD_ON_STARTUP="${LOCAL_STT_PRELOAD_ON_STARTUP:-1}"
export LOCAL_STT_PRELOAD_PROVIDERS="${LOCAL_STT_PRELOAD_PROVIDERS:-qwen}"
export LOCAL_STT_PRELOAD_ON_SWITCH="${LOCAL_STT_PRELOAD_ON_SWITCH:-1}"
export LOCAL_STT_FORCE_REALTIME_BUFFERED="${LOCAL_STT_FORCE_REALTIME_BUFFERED:-1}"
export LOCAL_STT_REALTIME_NO_SPEECH_GRACE_MS="${LOCAL_STT_REALTIME_NO_SPEECH_GRACE_MS:-0}"
export LOCAL_STT_REALTIME_FINAL_TRANSCRIPT_TIMEOUT_MS="${LOCAL_STT_REALTIME_FINAL_TRANSCRIPT_TIMEOUT_MS:-0}"
export FREE_TALK_CHAT_MODEL="${FREE_TALK_CHAT_MODEL:-gpt-5-nano}"
export FREE_TALK_TRANSLATE_ENABLED="${FREE_TALK_TRANSLATE_ENABLED:-1}"
export OPENAI_TTS_VOICE="${OPENAI_TTS_VOICE:-nova}"
export OPENAI_TTS_SPEED="${OPENAI_TTS_SPEED:-1.0}"
export CHAT_STREAM_FRAGMENT_CHARS="${CHAT_STREAM_FRAGMENT_CHARS:-12}"
export CHAT_STREAM_FRAGMENT_MIN_LEN="${CHAT_STREAM_FRAGMENT_MIN_LEN:-18}"
export CHAT_STREAM_FRAGMENT_DELAY_MS="${CHAT_STREAM_FRAGMENT_DELAY_MS:-0}"
export CHAT_WS_UID_LIMIT="${CHAT_WS_UID_LIMIT:-600}"
export CHAT_WS_IP_LIMIT="${CHAT_WS_IP_LIMIT:-600}"
export CHAT_WS_WINDOW_SEC="${CHAT_WS_WINDOW_SEC:-60}"
export CHAT_WS_SKIP_LOCAL_IP="${CHAT_WS_SKIP_LOCAL_IP:-1}"

echo "python: $("$PYTHON_BIN" -c 'import sys; print(sys.executable)')"
echo "active_provider=$LOCAL_STT_ACTIVE_PROVIDER qwen_isolate=$LOCAL_STT_QWEN_ISOLATE_PROCESS qwen_device_map=$LOCAL_STT_QWEN_DEVICE_MAP qwen_dtype=$LOCAL_STT_QWEN_DTYPE"
echo "preload_on_startup=$LOCAL_STT_PRELOAD_ON_STARTUP preload_providers=$LOCAL_STT_PRELOAD_PROVIDERS preload_on_switch=$LOCAL_STT_PRELOAD_ON_SWITCH"
echo "realtime_mode_forced_buffered=$LOCAL_STT_FORCE_REALTIME_BUFFERED"
echo "realtime_no_speech_grace_ms=$LOCAL_STT_REALTIME_NO_SPEECH_GRACE_MS realtime_final_timeout_ms=$LOCAL_STT_REALTIME_FINAL_TRANSCRIPT_TIMEOUT_MS"
echo "free_talk_chat_model=$FREE_TALK_CHAT_MODEL translate_enabled=$FREE_TALK_TRANSLATE_ENABLED"
echo "tts_voice=$OPENAI_TTS_VOICE tts_speed=$OPENAI_TTS_SPEED"
echo "chat_stream_fragment_chars=$CHAT_STREAM_FRAGMENT_CHARS min_len=$CHAT_STREAM_FRAGMENT_MIN_LEN delay_ms=$CHAT_STREAM_FRAGMENT_DELAY_MS"
echo "chat_ws_uid_limit=$CHAT_WS_UID_LIMIT ip_limit=$CHAT_WS_IP_LIMIT window_sec=$CHAT_WS_WINDOW_SEC skip_local_ip=$CHAT_WS_SKIP_LOCAL_IP"

existing_pid="$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
if [[ -n "$existing_pid" ]]; then
  existing_cmd="$(ps -p "$existing_pid" -o command= 2>/dev/null || true)"
  echo "port $PORT already in use by pid=$existing_pid"
  echo "command: $existing_cmd"
  if [[ "$existing_cmd" == *"app.main_local_stt:app"* ]]; then
    if [[ "$RESTART_IF_RUNNING" == "1" ]]; then
      echo "restarting existing local STT server to apply latest code..."
      kill "$existing_pid"
      sleep 0.3
    else
      echo "local STT server is already running. Reusing existing process."
      exit 0
    fi
  fi
  if [[ "$RESTART_IF_RUNNING" != "1" ]]; then
    echo "please stop the existing process first (e.g. kill $existing_pid)"
    exit 1
  fi
fi

if [[ "$ENABLE_RELOAD" == "1" ]]; then
  echo "server: app.main_local_stt:app port=$PORT reload=on"
  exec "$PYTHON_BIN" -m uvicorn app.main_local_stt:app --host 0.0.0.0 --port "$PORT" --reload
fi

echo "server: app.main_local_stt:app port=$PORT reload=off"
exec "$PYTHON_BIN" -m uvicorn app.main_local_stt:app --host 0.0.0.0 --port "$PORT"
