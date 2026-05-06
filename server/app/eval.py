# server/app/eval.py
from __future__ import annotations

# =========================
# 표준 라이브러리 임포트
# =========================
import os
import re
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Any, List, Tuple

# =========================
# 외부 라이브러리
# =========================
from pydantic import BaseModel, Field

# =========================
# 내부 유틸/로더
# =========================
# - 프롬프트 A/B 하네스: load_prompt, load_ab
# - 목표/표현 평가: load_goal_rules
from .config_loader import load_prompt, load_ab, load_goal_rules


# ======================================================================
# 공통 유틸
# ======================================================================
def clamp01(x: float) -> float:
    """[0,1] 범위로 값 고정"""
    return max(0.0, min(1.0, x))

def score_to_cefr(s: float) -> str:
    """총점(0~1)을 대략적 CEFR 등급으로 매핑"""
    if s < 0.25:
        return "A1"
    elif s < 0.40:
        return "A2"
    elif s < 0.55:
        return "B1"
    elif s < 0.70:
        return "B2"
    elif s < 0.85:
        return "C1"
    return "C2"


# ======================================================================
# Speaking 스코어링 (원본 유지)
# ======================================================================
class SpeakingMetrics(BaseModel):
    wpm: float = Field(..., ge=0, description="분당 단어수")
    silence_ratio: float = Field(..., ge=0, le=1, description="0~1 (침묵 비율)")
    filler_per_min: float = Field(..., ge=0, description="분당 추임새(uh/um) 개수")
    grammar_error_rate: float = Field(..., ge=0, description="100 토큰당 문법 오류수")
    cohesion: float = Field(..., ge=0, le=1, description="0~1 (응집도)")

def score_speaking(m: SpeakingMetrics) -> dict:
    # 간단한 휴리스틱 정규화
    wpm_score = clamp01((m.wpm - 70.0) / 70.0)                # ≥140 → 1.0
    silence_score = 1.0 - clamp01(m.silence_ratio / 0.35)     # 0.35 → 0.0
    filler_score = 1.0 - clamp01(m.filler_per_min / 8.0)      # 8 → 0.0
    grammar_score = 1.0 - clamp01(m.grammar_error_rate / 12.0)# 12 → 0.0
    cohesion_score = clamp01(m.cohesion)

    weights = dict(wpm=0.2, silence=0.2, filler=0.2, grammar=0.2, cohesion=0.2)
    total = (
        wpm_score * weights["wpm"]
        + silence_score * weights["silence"]
        + filler_score * weights["filler"]
        + grammar_score * weights["grammar"]
        + cohesion_score * weights["cohesion"]
    )
    return {
        "subscores": {
            "wpm_score": round(wpm_score, 3),
            "silence_score": round(silence_score, 3),
            "filler_score": round(filler_score, 3),
            "grammar_score": round(grammar_score, 3),
            "cohesion_score": round(cohesion_score, 3),
        },
        "total": round(total, 3),
        "cefr": score_to_cefr(total),
    }


# ======================================================================
# Writing 스코어링 (원본 유지)
# ======================================================================
class WritingMetrics(BaseModel):
    grammar_error_rate: float = Field(..., ge=0, description="100 단어당 문법 오류수")
    lexical_richness: float = Field(..., ge=0, le=1, description="0~1 (TTR 등)")
    cohesion: float = Field(..., ge=0, le=1, description="0~1 (응집도)")
    variety: float = Field(..., ge=0, le=1, description="0~1 (문장 다양성)")
    task: float = Field(..., ge=0, le=1, description="0~1 (과제 충족)")

def score_writing(m: WritingMetrics) -> dict:
    grammar_score = 1.0 - clamp01(m.grammar_error_rate / 10.0) # 10 → 0.0
    lexical = clamp01(m.lexical_richness)
    cohesion = clamp01(m.cohesion)
    variety = clamp01(m.variety)
    task = clamp01(m.task)

    weights = dict(grammar=0.35, lexical=0.20, cohesion=0.20, variety=0.10, task=0.15)
    total = (
        grammar_score * weights["grammar"]
        + lexical * weights["lexical"]
        + cohesion * weights["cohesion"]
        + variety * weights["variety"]
        + task * weights["task"]
    )
    return {
        "subscores": {
            "grammar_score": round(grammar_score, 3),
            "lexical": round(lexical, 3),
            "cohesion": round(cohesion, 3),
            "variety": round(variety, 3),
            "task": round(task, 3),
        },
        "total": round(total, 3),
        "cefr": score_to_cefr(total),
    }


# ======================================================================
# Goal/Phrase 달성 평가 (신규 추가 - eval/goal API용, 원본 통합)
# ======================================================================
_normalize_re = re.compile(r"[^a-z0-9\s]")

def _norm(s: str) -> List[str]:
    """간단 토크나이즈: 소문자화 + 비영숫자 제거 후 공백 분리"""
    return _normalize_re.sub(" ", s.lower()).split()

def _find_phrase_indices(tokens: List[str], phrase: str) -> List[int]:
    """문구(토큰 시퀀스)가 transcript 토큰에 등장하는 시작 인덱스들 반환"""
    ptoks = _norm(phrase)
    if not ptoks:
        return []
    out: List[int] = []
    n, m = len(tokens), len(ptoks)
    for i in range(0, n - m + 1):
        if tokens[i:i+m] == ptoks:
            out.append(i)
    return out

def evaluate_transcript(transcript: str, goalset_id: str, tone_override: str | None = None) -> Dict[str, Any]:
    """
    목표/표현 달성 스코어 계산:
      - coverage: 필수 표현 매칭 비율
      - tone_score: 간단한 톤 판정 (polite-formal / confident-formal)
      - 최종 score = w_coverage * coverage + w_tone * tone_score
    """
    cfg = load_goal_rules()
    goal = next((g for g in cfg["goalsets"] if g["id"] == goalset_id), None)
    if not goal:
        raise ValueError(f"Unknown goalset_id: {goalset_id}")

    tone_profile = tone_override or goal.get("tone_profile", "polite-formal")
    weights = goal["scoring"]["weights"]
    pass_threshold = goal["scoring"]["pass_threshold"]
    assist_threshold = goal["scoring"].get("assist_threshold", 0.5)

    toks = _norm(transcript)
    req = goal.get("required_phrases", [])
    hits: List[Dict[str, Any]] = []
    found_count = 0

    for p in req:
        idx = _find_phrase_indices(toks, p)
        found = len(idx) > 0
        if found:
            found_count += 1
        hits.append({"phrase": p, "found": found, "indices": idx})

    coverage = (found_count / max(1, len(req)))

    # MVP 톤 평가
    tone_score = 1.0
    tone_warnings: List[str] = []
    joined = " ".join(toks)

    if tone_profile == "polite-formal":
        if "please" not in toks and "thank" not in toks:
            tone_score = 0.6
            tone_warnings.append("Consider adding polite markers like 'please' or 'thank you'.")
    elif tone_profile == "confident-formal":
        hedges = {"maybe", "perhaps", "kind of", "sort of"}
        if any(h in joined for h in hedges):
            tone_score = 0.7
            tone_warnings.append("Avoid hedging; state strengths confidently.")

    score = weights["coverage"] * coverage + weights["tone"] * tone_score
    passed = score >= pass_threshold

    missing = [h["phrase"] for h in hits if not h["found"]]
    suggestions: List[str] = []
    if coverage < assist_threshold:
        tmpl = cfg.get("intervention_rules", {}).get("low_coverage", {}).get("message_templates", [])
        for m in missing[:2]:
            if tmpl:
                suggestions.append(tmpl[0].replace("{phrase}", m))
            else:
                suggestions.append(f"Try including the missing phrase: '{m}'.")

    return {
        "goalset_id": goalset_id,
        "coverage_ratio": round(coverage, 4),
        "score": round(score, 4),
        "passed": passed,
        "required_hits": hits,
        "missing_phrases": missing,
        "tone_score": round(tone_score, 4),
        "tone_warnings": tone_warnings,
        "suggestions": suggestions,
        "details": {
            "tone_profile": tone_profile,
            "weights": weights
        }
    }


# ======================================================================
# 프롬프트 A/B 하네스 (이전 제안 통합)
#   - 토큰 근사, 간단 채점 스텁, 리포트 JSON 저장
# ======================================================================
ROOT = Path(__file__).resolve().parents[1]         # .../server
PROMPTS_DIR = ROOT / "config" / "prompts"
DATA_DIR = ROOT / "data"
REPORT_DIR = DATA_DIR / "eval_reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

@dataclass
class Case:
    """examples.jsonl 한 줄 케이스"""
    id: str
    level: str
    user_text: str
    tags_truth: List[str]
    expect: str

def _read_jsonl(path: Path) -> List[Case]:
    """JSONL 파일을 Case 리스트로 로드"""
    out: List[Case] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        j = json.loads(line)
        out.append(Case(**j))
    return out

def _fmt_prompt(template: str, level: str, tags: List[str], user_text: str) -> str:
    """템플릿 변수 간단 치환"""
    return (template
            .replace("{{level}}", level)
            .replace("{{tags_csv}}", ",".join(tags))
            .replace("{{user_text}}", user_text))

def _token_estimate(s: str) -> int:
    """대략적 토큰 수 근사치(문자/토큰 혼합 기준)"""
    return int(len(re.findall(r"\w+|\S", s)) * 1.3)

def _call_llm(prompt: str) -> str:
    """
    LLM 호출 스텁.
    - OPENAI_API_KEY 없으면 규칙적 응답 반환(로컬 개발용)
    - 키가 있으면 여기서 실제 호출을 연결(추후 구현)
    """
    if not os.getenv("OPENAI_API_KEY"):
        if "Looks good" in prompt:
            return "Looks good."
        if "Yesterday I go" in prompt or "go to" in prompt:
            return "I went to the museum yesterday."
        return "Here's one quick tip: try shorter sentences."
    # TODO: 실제 OpenAI 호출 로직 연결
    return "Mock response."

def _judge(reply: str, case: Case) -> Dict[str, float]:
    """
    간단 채점 스텁:
      - 길면 brevity↓
      - 수정 없으면 under↑
      - 과도한 재작성은 over↑
    """
    brevity = 1.0 if len(reply) <= 120 else 0.5
    under = 0.8 if any(t in reply.lower() for t in ["went", "have been"]) else 0.2
    under = 1.0 - under  # penalty로 간주
    over = 0.3 if len(reply) > 200 else 0.1
    clarity = 0.8
    return {"over": over, "under": under, "clarity": clarity, "brevity": brevity}

def run_ab(abA: str, abB: str, examples_path: Path) -> Dict[str, Any]:
    """
    프롬프트 A/B 실험 실행 후 요약 리포트/저장 경로 반환
    """
    tpl = load_prompt("prompt_freetalk_v2.md")
    ab = load_ab()
    A, B = ab[abA], ab[abB]
    cases = _read_jsonl(examples_path)

    res: Dict[str, Dict[str, Any]] = {
        "A": {"n": 0, "tok_in": 0, "tok_out": 0, "m": []},
        "B": {"n": 0, "tok_in": 0, "tok_out": 0, "m": []},
    }

    for variant_key, cfg in (("A", A), ("B", B)):
        for c in cases:
            p = _fmt_prompt(tpl, c.level, c.tags_truth, c.user_text)
            pin = _token_estimate(p)
            reply = _call_llm(p)
            pout = _token_estimate(reply)
            j = _judge(reply, c)
            res[variant_key]["n"] += 1
            res[variant_key]["tok_in"] += pin
            res[variant_key]["tok_out"] += pout
            res[variant_key]["m"].append({"id": c.id, "j": j})

    # 가중 합산(루브릭 v2)
    weights = json.loads((ROOT / "config" / "rubrics" / "weights_v2.json").read_text(encoding="utf-8"))

    def aggregate(side: str) -> Dict[str, float]:
        m = res[side]["m"]
        over = sum(x["j"]["over"] for x in m) / max(1, len(m))
        under = sum(x["j"]["under"] for x in m) / max(1, len(m))
        clarity = sum(x["j"]["clarity"] for x in m) / max(1, len(m))
        brevity = sum(x["j"]["brevity"] for x in m) / max(1, len(m))
        score = (
            weights["clarity"] * clarity
            + weights["brevity"] * brevity
            - weights["over_penalty"] * over
            - weights["under_penalty"] * under
        )
        return {
            "over": round(over, 4),
            "under": round(under, 4),
            "clarity": round(clarity, 4),
            "brevity": round(brevity, 4),
            "score": round(score, 4),
        }

    res["A"]["agg"] = aggregate("A")
    res["B"]["agg"] = aggregate("B")

    t = int(time.time())
    out = {"ts": t, "A": res["A"], "B": res["B"]}
    out_path = REPORT_DIR / f"ab_{abA}_{abB}_{t}.json"
    out_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    return {"path": str(out_path), "summary": {"A": out["A"]["agg"], "B": out["B"]["agg"]}}


# ======================================================================
# CLI (옵션): A/B 실행 서브커맨드
#   사용 예)
#     uv run python -m app.eval ab --A A --B B --examples config/prompts/examples.jsonl
# ======================================================================
if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="eval 모듈: A/B 및 스코어링 유틸")
    sub = ap.add_subparsers(dest="cmd")

    # AB 서브커맨드
    abp = sub.add_parser("ab", help="프롬프트 A/B 실험 실행")
    abp.add_argument("--A", default="A", help="A 변이 키 (ab_sets.json)")
    abp.add_argument("--B", default="B", help="B 변이 키 (ab_sets.json)")
    abp.add_argument(
        "--examples",
        default=str(PROMPTS_DIR / "examples.jsonl"),
        help="평가 examples.jsonl 경로",
    )

    args = ap.parse_args()

    if args.cmd == "ab":
        r = run_ab(args.A, args.B, Path(args.examples))
        print(json.dumps(r, indent=2, ensure_ascii=False))
    else:
        ap.print_help()