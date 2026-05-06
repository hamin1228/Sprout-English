from __future__ import annotations

from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy import text

from app.config_loader import settings
from app.models import Base

DATABASE_URL: str = (
    f"mysql+asyncmy://{settings.DB_USER}:{settings.DB_PASSWORD}"
    f"@{settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}?charset=utf8mb4"
)

# [NEW] DB 커넥션 풀 튜닝: pool_size / max_overflow / pool_recycle 조정 (성능·안정성 개선)
engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
    pool_size=5,         # 동시 접속 수에 맞게 조정
    max_overflow=10,     # 피크 트래픽 시 추가 커넥션 허용
    pool_recycle=1800,   # 30분마다 커넥션 재생성 (MySQL/MariaDB idle timeout 회피)
    connect_args={"connect_timeout": 3},
    future=True,
)
SessionLocal = async_sessionmaker(
    bind=engine,
    expire_on_commit=False,
    class_=AsyncSession,
)

async def init_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))

async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session
