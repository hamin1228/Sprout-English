# FILE: english_ai/server/app/usage.py
from __future__ import annotations
from typing import Optional, Any, Dict
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import BigInteger, String, Integer, DateTime, JSON, Numeric, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import Base

class UsageLog(Base):
    __tablename__ = "usage_logs"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    ts: Mapped[Any] = mapped_column(DateTime(True), server_default=func.now())
    route: Mapped[str] = mapped_column(String(64))
    uid: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    tokens_in: Mapped[int] = mapped_column(Integer, default=0)
    tokens_out: Mapped[int] = mapped_column(Integer, default=0)
    cost_usd: Mapped[Optional[float]] = mapped_column(Numeric(10,5), nullable=True)
    latency_ms: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    extra: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON, nullable=True)

async def record_usage(
    session: AsyncSession,
    *,
    route: str,
    uid: Optional[str],
    ip: Optional[str],
    tokens_in: int = 0,
    tokens_out: int = 0,
    cost_usd: Optional[float] = None,
    latency_ms: Optional[int] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> None:
    log = UsageLog(
        route=route, uid=uid, ip=ip,
        tokens_in=tokens_in, tokens_out=tokens_out,
        cost_usd=cost_usd, latency_ms=latency_ms, extra=extra
    )
    session.add(log)
    await session.commit()