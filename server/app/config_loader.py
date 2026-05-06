from pydantic_settings import BaseSettings
from pydantic import Field

class Settings(BaseSettings):
    DB_USER: str = "ea"
    DB_PASSWORD: str = "ea_pw"
    DB_HOST: str = "127.0.0.1"
    DB_PORT: int = 3306
    DB_NAME: str = "english_ai"

    # Embedding / VectorStore
    EMBED_PROVIDER: str = Field(default="toy")  # toy | faiss-openai(예비)
    EMBED_DIM: int = Field(default=384)
    VECTOR_ROOT: str = Field(default="server/data/vector")

    class Config:
        env_file = "server/.env"

settings = Settings()