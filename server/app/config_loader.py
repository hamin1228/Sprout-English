from __future__ import annotations
from typing import List
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    # ── Database ────────────────────────────────────────────────────────────
    DB_USER: str = "ea"
    DB_PASSWORD: str = "ea_pw"
    DB_HOST: str = "127.0.0.1"
    DB_PORT: int = 3306
    DB_NAME: str = "english_ai"

    # ── OpenAI ──────────────────────────────────────────────────────────────
    OPENAI_API_KEY: str = ""
    OPENAI_CHAT_MODEL: str = "gpt-4o-mini"
    OPENAI_WHISPER_MODEL: str = ""          # 빈 문자열 = Whisper API 기본값 사용
    OPENAI_TTS_MODEL: str = "gpt-4o-mini-tts"
    OPENAI_TTS_VOICE: str = "nova"
    OPENAI_TTS_SPEED: str = "1.0"

    # ── Redis ────────────────────────────────────────────────────────────────
    REDIS_URL: str = "redis://localhost:6379/0"

    # ── Storage ──────────────────────────────────────────────────────────────
    STORAGE_LOCAL_PATH: str = "./app/storage"

    # ── CORS ─────────────────────────────────────────────────────────────────
    # 쉼표로 구분된 허용 Origin 목록.
    # 개발: * (모든 origin 허용, credentials 비활성화)
    # 운영: https://your-domain.com,https://other-domain.com
    CORS_ORIGINS: str = "*"

    # ── Embedding / VectorStore ──────────────────────────────────────────────
    EMBED_PROVIDER: str = Field(default="toy")   # toy | faiss-openai
    EMBED_DIM: int = Field(default=384)
    VECTOR_ROOT: str = Field(default="server/data/vector")

    # ── JWT ──────────────────────────────────────────────────────────────────
    # 운영 환경에서는 반드시 강한 랜덤 문자열로 교체해야 한다.
    # 예: openssl rand -hex 32
    JWT_SECRET_KEY: str = "change-this-to-a-long-random-secret"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 14

    # ── App ───────────────────────────────────────────────────────────────────
    APP_ENV: str = "development"             # development | production
    LOG_LEVEL: str = "INFO"

    class Config:
        env_file = "server/.env"


settings = Settings()


def get_cors_origins() -> List[str]:
    """CORS_ORIGINS 환경변수를 파싱해 리스트로 반환한다."""
    raw = settings.CORS_ORIGINS.strip()
    if raw == "*":
        return ["*"]
    return [o.strip() for o in raw.split(",") if o.strip()]


def get_cors_allow_credentials() -> bool:
    """allow_origins=['*'] 와 allow_credentials=True 조합은 브라우저 정책 위반이다.
    '*' 이외의 명시적 origin이 설정된 경우에만 credentials를 허용한다."""
    return get_cors_origins() != ["*"]
