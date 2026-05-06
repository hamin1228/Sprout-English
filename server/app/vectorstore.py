# [NEW] VectorStore 모듈 (파일 기반 + 선택적 FAISS 가속)
# - 목적: 간단한 디스크 영속 벡터 인덱스. 네임스페이스별(.npz/.jsonl) 저장
# - 임베딩 형상: (N, dim) float32. 질의는 (1, dim) 2D 유지
# - 동시성: 네임스페이스별 asyncio.Lock으로 upsert/query 중 레이스 방지
# - 의존성: FAISS가 있으면 IP(내적)+L2 정규화로 검색, 없으면 NumPy 코사인 유사도 fallback
import os, json, asyncio
import numpy as np
from typing import List, Dict, Any
from dataclasses import dataclass

# [NEW] FAISS 선택적 의존성
# - 설치되어 있으면 고속 최근접 탐색(IndexFlatIP + normalize_L2)
# - 미설치 시에도 동작하도록 NumPy 기반 경로 사용
try:
    import faiss  # 선택
    HAS_FAISS = True
except Exception:
    HAS_FAISS = False

# [NEW] VSItem: 인덱싱할 단일 문서/레코드 표현
# - ref_id: 외부 식별자(예: "mistake:{id}")
# - text: 임베딩 대상 텍스트
# - meta: JSON 직렬화 가능한 부가 정보(별도 .jsonl 로 저장)
@dataclass
class VSItem:
    ref_id: str
    text: str
    meta: Dict[str, Any] | None = None

# [NEW] VectorStore: 네임스페이스별 디스크 백엔드 벡터 스토어
# - 루트 폴더 아래 {namespace}.npz(embs/ref_ids/texts), {namespace}.jsonl(meta) 관리
# - 간단한 파일 포맷으로 Git 없이도 공유/백업 용이
class VectorStore:
    # [NEW] 생성자: 저장 루트/차원 설정 및 네임스페이스별 Lock 준비
    def __init__(self, root: str, dim: int):
        self.root = root
        self.dim = dim
        self._locks: Dict[str, asyncio.Lock] = {}
        os.makedirs(root, exist_ok=True)

    # [NEW] 내부 경로 유틸: ns -> (npz 경로, jsonl 경로)
    def _paths(self, ns: str):
        return (os.path.join(self.root, f"{ns}.npz"), os.path.join(self.root, f"{ns}.jsonl"))

    # [NEW] 네임스페이스 단위 Lock 획득(없으면 생성)
    def _lock(self, ns: str) -> asyncio.Lock:
        if ns not in self._locks: self._locks[ns] = asyncio.Lock()
        return self._locks[ns]

    # [NEW] 디스크 로드
    # - 존재 시: embs(float32), ref_ids(bytes->str), texts(bytes->str), metas(jsonl)
    # - 없을 때: embs=(0, dim)으로 초기화하여 빈 인덱스 표준화
    def _load(self, ns: str):
        npz_path, meta_path = self._paths(ns)
        if os.path.exists(npz_path):
            data = np.load(npz_path)
            embs = data["embs"].astype(np.float32)
            ref_ids = list(map(lambda s: s.decode("utf-8"), data["ref_ids"]))
            texts = list(map(lambda s: s.decode("utf-8"), data["texts"]))
        else:
            embs = np.zeros((0, self.dim), dtype=np.float32)
            ref_ids, texts = [], []
        metas: List[dict] = []
        if os.path.exists(meta_path):
            with open(meta_path, "r", encoding="utf-8") as f:
                metas = [json.loads(line) for line in f]
        return embs, ref_ids, texts, metas

    # [NEW] 디스크 저장
    # - .npz: embs(2D), ref_ids(S-타입 바이트 배열), texts(S-타입 바이트 배열)
    # - .jsonl: meta 레코드 라인 단위 기록
    def _save(self, ns: str, embs: np.ndarray, ref_ids: List[str], texts: List[str], metas: List[dict]):
        npz_path, meta_path = self._paths(ns)
        np.savez_compressed(npz_path, embs=embs, ref_ids=np.array(ref_ids, dtype="S"), texts=np.array(texts, dtype="S"))
        with open(meta_path, "w", encoding="utf-8") as f:
            for m in metas: f.write(json.dumps(m, ensure_ascii=False) + "\n")

    # [NEW] Upsert
    # - embeddings: (N, dim) float32 전제, 기존 embs 뒤에 수직 결합(vstack)
    # - ref_ids/texts/metas 를 동일 순서로 append하여 행 정렬 유지
    async def upsert(self, ns: str, embeddings: np.ndarray, items: List[VSItem]):
        async with self._lock(ns):
            embs, ref_ids, texts, metas = self._load(ns)
            embs = np.vstack([embs, embeddings]) if embs.size else embeddings
            ref_ids.extend([it.ref_id for it in items])
            texts.extend([it.text for it in items])
            metas.extend([{"ref_id": it.ref_id, **(it.meta or {})} for it in items])
            self._save(ns, embs, ref_ids, texts, metas)

    # [NEW] Query
    # - 입력 query_emb 는 (1, dim) 2D 전제
    # - FAISS: IndexFlatIP + L2 정규화(코사인 동등) / Fallback: NumPy 코사인
    # - 반환: rank/score/ref_id/text/meta 로 구성된 리스트
    async def query(self, ns: str, query_emb: np.ndarray, top_k: int = 5):
        async with self._lock(ns):
            embs, ref_ids, texts, metas = self._load(ns)
            if embs.shape[0] == 0:
                return []
            q = query_emb.astype(np.float32)
            if HAS_FAISS:
                index = faiss.IndexFlatIP(self.dim)
                faiss.normalize_L2(embs)
                faiss.normalize_L2(q)
                index.add(embs)
                scores, idxs = index.search(q, top_k)
            else:
                # NumPy 내적 기반 코사인 (L2 정규화 가정)
                embs_n = embs / (np.linalg.norm(embs, axis=1, keepdims=True) + 1e-12)
                qn = q / (np.linalg.norm(q, axis=1, keepdims=True) + 1e-12)
                scores = qn @ embs_n.T
                idxs = np.argsort(-scores, axis=1)[:, :top_k]
                scores = np.take_along_axis(scores, idxs, axis=1)

            out = []
            for rank, (i, sc) in enumerate(zip(idxs[0], scores[0])):
                out.append({"rank": rank+1, "score": float(sc), "ref_id": ref_ids[i], "text": texts[i], "meta": metas[i] if i < len(metas) else {}})
            return out

    # [NEW] Stats
    # - 루트 폴더의 *.npz 를 스캔하여 네임스페이스별 벡터 개수 집계
    def stats(self) -> Dict[str, Any]:
        out = {}
        for fn in os.listdir(self.root):
            if fn.endswith(".npz"):
                ns = fn[:-4]
                arr = np.load(os.path.join(self.root, fn))
                out[ns] = int(arr["embs"].shape[0])
        return out