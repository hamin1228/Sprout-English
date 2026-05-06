from __future__ import annotations
import random, yaml
from pathlib import Path
from typing import List, Dict, Set

_POLICY = Path(__file__).resolve().parents[2] / "config" / "expression_policy.yaml"

def _load_policy():
    return yaml.safe_load(_POLICY.read_text(encoding="utf-8"))

def _choose(pool: List[str], k: int) -> List[str]:
    if k <= 0: return []
    if k >= len(pool): return pool[:]
    return random.sample(pool, k=k)

def generate_expressions(user_level: str, history_tags: List[str], exclude_recent: Set[str], n: int, diversity: float):
    policy = _load_policy()
    lv = policy["levels"].get(user_level, {})
    pools: Dict[str, List[str]] = lv.get("pools", {})
    bias_map: Dict[str, List[str]] = policy.get("bias_by_tag", {})

    # 후보(레벨 공통 + 이력 태그 가중)
    candidates: List[Dict] = []

    # 레벨 범용
    for t, phs in pools.items():
        tag_key = None if t == "general" else t
        for p in phs:
            if p not in exclude_recent:
                candidates.append({"text": p, "tag_bias": tag_key, "level": user_level, "score": 0.0})

    # 태그 바이어스
    for t in history_tags:
        for p in bias_map.get(t, []):
            if p not in exclude_recent:
                candidates.append({"text": p, "tag_bias": t, "level": user_level, "score": 0.0})

    # 점수: 다양성 + 태그 매칭
    seen = set()
    for c in candidates:
        base = 1.0 if c["tag_bias"] else 0.6
        # 간단한 다양성 보정(문장 시작어 기준)
        prefix = c["text"].split(" ", 1)[0].lower()
        if prefix in seen:
            base *= (0.5 + 0.5 * (1.0 - diversity))
        else:
            seen.add(prefix)
        c["score"] = base

    # 상위 n 선택
    candidates.sort(key=lambda x: x["score"], reverse=True)
    picked = []
    used_prefix = set()
    for c in candidates:
        pref = c["text"].split(" ", 1)[0].lower()
        if pref in used_prefix:
            continue
        picked.append(c)
        used_prefix.add(pref)
        if len(picked) >= n:
            break

    # 합리화(로그 용)
    for c in picked:
        r = []
        if c["tag_bias"]: r.append(f"biased_by={c['tag_bias']}")
        c["rationale"] = "; ".join(r) if r else "policy/general"
    return picked