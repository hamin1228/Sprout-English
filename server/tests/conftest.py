"""
pytest 공통 설정: 실제 DB/Redis/OpenAI 없이 테스트 가능하도록
모든 필수 환경변수를 미리 설정한다.
이 모듈은 테스트 파일보다 먼저 로드되므로 pydantic_settings가
Settings를 생성할 때 가짜 값을 읽는다.
"""
import os
import tempfile

# StaticFiles 마운트가 모듈 임포트 시 디렉토리 존재를 확인하므로 미리 생성한다.
_TEST_STORAGE = os.path.join(tempfile.gettempdir(), "sprout_test_storage")
os.makedirs(_TEST_STORAGE, exist_ok=True)

_DEFAULTS = {
    "DB_USER": "testuser",
    "DB_PASSWORD": "testpass",
    "DB_HOST": "127.0.0.1",
    "DB_PORT": "3306",
    "DB_NAME": "test_db",
    "OPENAI_API_KEY": "sk-fake-key-for-testing-only",
    "OPENAI_CHAT_MODEL": "gpt-4o-mini",
    "OPENAI_WHISPER_MODEL": "",
    "OPENAI_TTS_MODEL": "gpt-4o-mini-tts",
    "OPENAI_TTS_VOICE": "nova",
    "OPENAI_TTS_SPEED": "1.0",
    "REDIS_URL": "redis://localhost:6379/0",
    "STORAGE_LOCAL_PATH": _TEST_STORAGE,
    "CORS_ORIGINS": "*",
    "APP_ENV": "test",
    "LOG_LEVEL": "ERROR",
    "MYSQL_ROOT_PASSWORD": "testroot",
    "JWT_SECRET_KEY": "test-secret-key-for-testing-only",
    "JWT_ALGORITHM": "HS256",
    "ACCESS_TOKEN_EXPIRE_MINUTES": "60",
    "REFRESH_TOKEN_EXPIRE_DAYS": "14",
}

for key, value in _DEFAULTS.items():
    os.environ.setdefault(key, value)
