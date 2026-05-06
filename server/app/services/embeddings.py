import hashlib
import numpy as np
from typing import List

class BaseEmbedder:
    def __init__(self, dim: int = 384): self.dim = dim
    async def embed(self, texts: List[str]) -> np.ndarray: raise NotImplementedError

class ToyEmbedder(BaseEmbedder):
    """외부 키 없이 동작하는 해시 기반 고정 임베딩(테스트/개발용)."""
    async def embed(self, texts: List[str]) -> np.ndarray:
        out = np.zeros((len(texts), self.dim), dtype=np.float32)
        for i, t in enumerate(texts):
            tokens = t.lower().split()
            for tok in tokens:
                h = int(hashlib.md5(tok.encode()).hexdigest(), 16)
                idx = h % self.dim
                out[i, idx] += 1.0
            # L2 normalize
            norm = np.linalg.norm(out[i]) or 1.0
            out[i] = out[i] / norm
        return out

class HashEmbedder(BaseEmbedder):
    """SHA256 기반 토큰 평균 임베딩(안정적, 차원 고정)."""
    def _tokenize(self, text: str) -> List[str]:
        return [t for t in text.lower().split() if t.strip()]

    def _tok2vec(self, tok: str) -> np.ndarray:
        h = hashlib.sha256(tok.encode("utf-8")).digest()
        v = np.frombuffer(h, dtype=np.uint8).astype(np.float32)
        # dim 길이에 맞게 반복/자르기
        reps = (self.dim + len(v) - 1) // len(v)
        v = np.concatenate([v] * reps)[: self.dim]
        # L2 normalize
        v /= (np.linalg.norm(v) + 1e-8)
        return v

    async def embed(self, texts: List[str]) -> np.ndarray:
        out = []
        for t in texts:
            toks = self._tokenize(t)[:64]  # 긴 문장은 상한
            if not toks:
                out.append(np.zeros(self.dim, dtype=np.float32))
                continue
            vecs = [self._tok2vec(tok) for tok in toks]
            v = np.mean(vecs, axis=0)
            v /= (np.linalg.norm(v) + 1e-8)
            out.append(v.astype(np.float32))
        return np.stack(out, axis=0)

def build_embedder(provider: str = "toy", dim: int = 384):
    # 확장 포인트: provider == "st" (sentence-transformers) 등으로 교체 가능
    prov = (provider or "toy").lower()
    if prov in ("hash", "sha", "sha256"):
        return HashEmbedder(dim=dim)
    if prov in ("toy", "bow", "md5"):
        return ToyEmbedder(dim=dim)
    # 기본값
    return ToyEmbedder(dim=dim)