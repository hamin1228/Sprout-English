from __future__ import annotations

import asyncio
import logging
from logging.config import fileConfig
from pathlib import Path
import sys

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import create_async_engine

# ---- 프로젝트 루트(server/)를 import 경로에 추가 ----
BASE_DIR = Path(__file__).resolve().parents[1]  # server/
sys.path.append(str(BASE_DIR))

# 우리 프로젝트의 Base/DSN 사용
from app.db import Base, settings  # settings.dsn = "mysql+asyncmy://...?...charset=utf8mb4"

# ---- Alembic 설정 객체 ----
config = context.config

# ---- 로깅 가드: ini가 불완전해도 죽지 않도록 ----
cfg_file = config.config_file_name
if cfg_file is not None and Path(cfg_file).exists():
    try:
        fileConfig(cfg_file)
    except Exception:
        logging.basicConfig(level=logging.INFO)
else:
    logging.basicConfig(level=logging.INFO)

# 자동 생성용 메타데이터
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """오프라인 모드: DB 접속 없이 SQL만 생성"""
    # async 드라이버를 동기 문자열로 교체 (오프라인은 실제 접속을 안 함)
    url = settings.dsn.replace("mysql+asyncmy", "mysql")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        compare_type=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    """동기 연결 컨텍스트에서 실제 마이그레이션 실행"""
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """온라인 모드: async 엔진으로 접속"""
    connectable = create_async_engine(settings.dsn, poolclass=pool.NullPool)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
