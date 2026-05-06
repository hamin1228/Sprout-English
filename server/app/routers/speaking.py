# server/app/models/speaking.py
from __future__ import annotations
from sqlalchemy import String, Text, Integer, Float, Index, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.mysql import BIGINT, DATETIME
from app.db import Base

class SpeakingScore(Base):
    __tablename__ = "scores_speaking"

    id: Mapped[int] = mapped_column(BIGINT(unsigned=True), primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    session_id: Mapped[str | None] = mapped_column(String(64), nullable=True)

    transcript: Mapped[str] = mapped_column(Text, nullable=False)
    duration_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    words: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    wpm: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    silence_ms_total: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    filler_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    filler_density: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    rule_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    llm_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    final_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[str] = mapped_column(
        DATETIME(fsp=6),
        server_default=func.now(),
        nullable=False,
    )

    __table_args__ = (
        Index("ix_scores_speaking_user_created", "user_id", "created_at"),
    )