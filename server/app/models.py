from __future__ import annotations
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from sqlalchemy import String, Text, Integer, Float, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.dialects.mysql import JSON as MySQLJSON
from sqlalchemy.sql import func
from sqlalchemy import Index, BigInteger, JSON


class Base(DeclarativeBase):
    pass

class Mistake(Base):
    __tablename__ = "mistakes"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="app")
    prompt_id: Mapped[Optional[str]] = mapped_column(String(64))
    text: Mapped[str] = mapped_column(Text)          # 오답 원문
    correction: Mapped[Optional[str]] = mapped_column(Text)  # 정정/해설
    tags: Mapped[Optional[str]] = mapped_column(String(255)) # "grammar, tense" 등 콤마 구분
    difficulty: Mapped[int] = mapped_column(Integer, default=2)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))
    srs_state: Mapped["SRSState"] = relationship(back_populates="mistake", uselist=False, cascade="all, delete-orphan")

class SRSState(Base):
    __tablename__ = "srs_states"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    mistake_id: Mapped[int] = mapped_column(ForeignKey("mistakes.id", ondelete="CASCADE"), unique=True)
    ease: Mapped[float] = mapped_column(Float, default=2.5)
    interval_days: Mapped[float] = mapped_column(Float, default=1.0)
    reps: Mapped[int] = mapped_column(Integer, default=0)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    last_reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    mistake: Mapped[Mistake] = relationship(back_populates="srs_state")

class Review(Base):
    __tablename__ = "reviews"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    mistake_id: Mapped[int] = mapped_column(ForeignKey("mistakes.id", ondelete="CASCADE"))
    quality: Mapped[int] = mapped_column(Integer)  # 0~5
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class VocabCard(Base):
    __tablename__ = "vocab_cards"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    lemma: Mapped[str] = mapped_column(String(128), nullable=False)
    meaning_ko: Mapped[str] = mapped_column(String(255), nullable=False)
    example_en: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    difficulty: Mapped[int] = mapped_column(Integer, nullable=False, default=2)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="manual")
    tags: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    pos: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))
    srs_state: Mapped["VocabSRSState"] = relationship(back_populates="card", uselist=False, cascade="all, delete-orphan")


class VocabSRSState(Base):
    __tablename__ = "vocab_srs_states"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    card_id: Mapped[int] = mapped_column(ForeignKey("vocab_cards.id", ondelete="CASCADE"), unique=True)
    ease: Mapped[float] = mapped_column(Float, default=2.5)
    interval_days: Mapped[float] = mapped_column(Float, default=1.0)
    reps: Mapped[int] = mapped_column(Integer, default=0)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    last_reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    card: Mapped[VocabCard] = relationship(back_populates="srs_state")


class VocabReviewLog(Base):
    __tablename__ = "vocab_review_logs"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    card_id: Mapped[int] = mapped_column(ForeignKey("vocab_cards.id", ondelete="CASCADE"))
    grade: Mapped[str] = mapped_column(String(16), nullable=False)
    quality: Mapped[int] = mapped_column(Integer, nullable=False)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class SpeakingScore(Base):
    """스피킹(말하기) 세션별 평가 결과.
    - total_score는 rule_score/gpt_score 등을 종합한 값
    - feedback에는 개선 포인트 등의 구조화된 JSON이 저장됨
    """
    __tablename__ = 'scores_speaking'
    __table_args__ = (
        Index('idx_scores_speaking_user_created', 'user_id', 'created_at'),
        Index('idx_scores_speaking_session', 'session_id'),
    )
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64), nullable=False)
    session_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    transcript: Mapped[str] = mapped_column(Text, nullable=False)
    duration_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    words: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    wpm: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    filler_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    silence_ratio: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    rule_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    gpt_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    total_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    feedback: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    # 서버 타임스탬프. timezone=True 로 UTC 저장. 생성 시 DB가 자동으로 채움
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

class WritingScore(Base):
    __tablename__ = 'scores_writing'
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str | None] = mapped_column(String(64), index=True, nullable=True)
    input_text: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_text: Mapped[str] = mapped_column(Text, nullable=False, default='')
    result_edits: Mapped[dict] = mapped_column(MySQLJSON, nullable=False, default=dict)
    result_checklist: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    result_warnings: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    score: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    model_name: Mapped[str] = mapped_column(String(64), nullable=False, default='gpt-5-nano')
    guidance_version: Mapped[str] = mapped_column(String(64), nullable=False, default='writing_eval_v1_20251011')
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
    # 생성/수정 타임스탬프: DB에서 now()로 채움 (응답 직전 refresh로 보장)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=func.now())
    # 업데이트 시 DB가 갱신
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=func.now(), onupdate=func.now())
    
    # --- 수정된 부분: lazy 로딩 전략을 'selectin'으로 변경 ---
    # 관계: selectin eager-load (쿼리 시점 일괄 로딩; 접근 시 추가 쿼리 없음)
    audits: Mapped[list['WritingScoreAudit']] = relationship(
        back_populates='score', cascade='all, delete-orphan', lazy='selectin'
    )

class WritingScoreAudit(Base):
    """WritingScore의 변경 이력 테이블.
    - action: 'create' / 'update' / 'delete'
    - snapshot: 변경 직전/직후 스냅샷(JSON)
    """
    __tablename__ = 'scores_writing_audit'
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    score_id: Mapped[int] = mapped_column(ForeignKey('scores_writing.id', ondelete='CASCADE'), index=True)
    action: Mapped[str] = mapped_column(String(16), nullable=False)
    snapshot: Mapped[dict] = mapped_column(MySQLJSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=func.now())
    score: Mapped["WritingScore"] = relationship(back_populates="audits")


class ToeicWritingScore(Base):
    __tablename__ = 'scores_toeic_writing'
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str | None] = mapped_column(String(64), index=True, nullable=True)
    task_type: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    prompt_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    prompt_meta: Mapped[dict] = mapped_column(MySQLJSON, nullable=False, default=dict)
    submission: Mapped[dict] = mapped_column(MySQLJSON, nullable=False, default=dict)
    rubric: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    overall_score: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    model_answer: Mapped[str] = mapped_column(Text, nullable=False, default='')
    sentence_feedback: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    corrections: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    checklist: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    next_actions: Mapped[list] = mapped_column(MySQLJSON, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=func.now(), index=True)
