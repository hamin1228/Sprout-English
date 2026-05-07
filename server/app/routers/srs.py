from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Body, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import _maybe_await, log
from app.db import get_session
from app.models import Mistake, SRSState
from app.schemas import MistakeCreate, MistakeOut, QueryReq, ReviewIn, SRSItem, UpsertReq
from app.services.embeddings import build_embedder
from app.services.srs import apply_review, ensure_initial_state
from app.vectorstore import VectorStore, VSItem
from app.config_loader import settings

router = APIRouter()

EMBED_DIM = getattr(settings, "EMBED_DIM", 384)
VECTOR_ROOT = getattr(settings, "VECTOR_ROOT", "server/data/vector")
EMBED_PROVIDER = getattr(settings, "EMBED_PROVIDER", "hash")
_embedder = build_embedder(EMBED_PROVIDER, EMBED_DIM)
_vstore = VectorStore(VECTOR_ROOT, EMBED_DIM)


@router.post("/mistakes", response_model=MistakeOut)
async def create_mistake(payload: MistakeCreate, db: AsyncSession = Depends(get_session)):
    m = Mistake(
        user_id=payload.user_id, text=payload.text, correction=payload.correction,
        tags=payload.tags, difficulty=payload.difficulty, prompt_id=payload.prompt_id,
    )
    db.add(m)
    await db.flush()
    state = await ensure_initial_state(db, m)

    if payload.index:
        text_for_emb = payload.text + (" " + payload.correction if payload.correction else "")
        emb = await _embedder.embed([text_for_emb])
        if getattr(emb, "ndim", 2) == 1:
            emb = emb.reshape(1, -1)
        await _vstore.upsert(
            payload.namespace,
            emb,
            [VSItem(ref_id=f"mistake:{m.id}", text=payload.text, meta={"mistake_id": m.id, "tags": payload.tags})],
        )

    await db.commit()
    return MistakeOut(id=m.id, text=m.text, correction=m.correction, tags=m.tags, due_at=state.due_at)


@router.get("/srs/next", response_model=list[SRSItem])
async def srs_next(limit: int = 20, db: AsyncSession = Depends(get_session)):
    now = datetime.now(timezone.utc)
    q = await db.execute(
        select(Mistake, SRSState)
        .join(SRSState, SRSState.mistake_id == Mistake.id)
        .where(SRSState.due_at <= now)
        .order_by(SRSState.due_at.asc())
        .limit(limit)
    )
    return [SRSItem(id=m.id, text=m.text, correction=m.correction, due_at=s.due_at) for (m, s) in q.all()]


@router.post("/srs/review", response_model=MistakeOut)
async def srs_review(payload: ReviewIn, db: AsyncSession = Depends(get_session)):
    m = await db.get(Mistake, payload.mistake_id)
    if not m:
        raise HTTPException(404, "mistake not found")
    state = await apply_review(db, payload.mistake_id, payload.quality)
    await db.commit()
    return MistakeOut(id=m.id, text=m.text, correction=m.correction, tags=m.tags, due_at=state.due_at)


@router.post("/index/upsert")
async def index_upsert(req: UpsertReq):
    texts = [it.text for it in req.items]
    emb = await _embedder.embed(texts)
    if getattr(emb, "ndim", 2) == 1:
        emb = emb.reshape(1, -1)
    items = [VSItem(ref_id=it.ref_id, text=it.text, meta=it.meta) for it in req.items]
    await _maybe_await(_vstore.upsert(req.namespace, emb, items))
    return {"ok": True, "count": len(items)}


@router.post("/index/query")
async def index_query(req: QueryReq):
    qemb = await _embedder.embed([req.query])
    if getattr(qemb, "ndim", 2) == 1:
        qemb = qemb.reshape(1, -1)
    hits = await _maybe_await(_vstore.query(req.namespace, qemb, top_k=req.top_k))
    return {"ok": True, "hits": hits}


@router.get("/index/stats")
async def index_stats():
    return await _maybe_await(_vstore.stats())


@router.post("/index/rebuild")
async def index_rebuild(
    namespace: str = Body("mistakes"),
    batch_size: int = Body(64),
    db: AsyncSession = Depends(get_session),
):
    total = 0
    offset = 0
    while True:
        res = await db.execute(select(Mistake).order_by(Mistake.id.asc()).offset(offset).limit(batch_size))
        ms = res.scalars().all()
        if not ms:
            break
        texts = [(m.text or "") + ((" " + m.correction) if m.correction else "") for m in ms]
        emb = await _embedder.embed(texts)
        if getattr(emb, "ndim", 2) == 1:
            emb = emb.reshape(1, -1)
        items = [VSItem(ref_id=f"mistake:{m.id}", text=m.text or "", meta={"mistake_id": m.id, "tags": m.tags}) for m in ms]
        await _maybe_await(_vstore.upsert(namespace, emb, items))
        total += len(ms)
        offset += len(ms)
    return {"ok": True, "namespace": namespace, "indexed": total, "dim": EMBED_DIM}


@router.post("/mistakes/search")
async def mistakes_search(
    q: str = Body(..., embed=True),
    top_k: int = Body(5, embed=True),
    namespace: str = Body("mistakes", embed=True),
    db: AsyncSession = Depends(get_session),
):
    qemb = await _embedder.embed([q])
    if getattr(qemb, "ndim", 2) == 1:
        qemb = qemb.reshape(1, -1)
    hits = await _maybe_await(_vstore.query(namespace, qemb, top_k=top_k))

    def _mid(ref):
        m = re.match(r"mistake:(\d+)$", str(ref or ""))
        return int(m.group(1)) if m else None

    ids = [i for i in [_mid(h.get("ref_id")) for h in hits] if i is not None]
    if not ids:
        return {"ok": True, "hits": []}
    res = await db.execute(select(Mistake).where(Mistake.id.in_(ids)))
    rows = {m.id: m for m in res.scalars().all()}
    out = []
    for h in hits:
        mid = _mid(h.get("ref_id"))
        m = rows.get(mid)
        if m:
            out.append({"score": float(h.get("score", 0.0)), "ref_id": h.get("ref_id"), "mistake": {"id": m.id, "text": m.text, "correction": m.correction, "tags": m.tags}})
    return {"ok": True, "hits": out}
