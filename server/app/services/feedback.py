from pathlib import Path
from typing import Tuple, Dict, Any, List
from .schemas import RubricWeights

BASE_DIR = Path(__file__).resolve().parents[1]
RUBRIC_PATH = BASE_DIR / "config" / "rubrics" / "rubric_weights.json"
TEMPLATE_PATH = BASE_DIR / "config" / "prompts" / "feedback_template.md"

def ensure_dirs():
    (BASE_DIR / "config" / "rubrics").mkdir(parents=True, exist_ok=True)
    (BASE_DIR / "config" / "prompts").mkdir(parents=True, exist_ok=True)

def load_weights() -> RubricWeights:
    ensure_dirs()
    if not RUBRIC_PATH.exists():
        w = RubricWeights()
        save_weights(w)
        return w
    import json
    with open(RUBRIC_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    w = RubricWeights(
        pronunciation=float(data.get("pronunciation", 0.40)),
        fluency=float(data.get("fluency", 0.35)),
        logic=float(data.get("logic", 0.25)),
    )
    return w

def save_weights(weights: RubricWeights) -> None:
    ensure_dirs()
    import json
    with open(RUBRIC_PATH, "w", encoding="utf-8") as f:
        json.dump(
            {
                "pronunciation": float(weights.pronunciation),
                "fluency": float(weights.fluency),
                "logic": float(weights.logic),
                "_notes": "합이 1이 아니어도 서버가 정규화합니다. 음수는 불가."
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

def load_template() -> str:
    ensure_dirs()
    if not TEMPLATE_PATH.exists():
        # 최소 템플릿 자동 생성
        default = (
            "# Mini Feedback (auto)\n\n"
            "**Overall**: {overall}/100\n"
            "Weights → Pron: {pron_w}, Flu: {flu_w}, Logic: {logic_w}\n\n"
            "### Example\n- Before: {example_before}\n- After: {example_after}\n\n"
            "{tips}\n"
        )
        with open(TEMPLATE_PATH, "w", encoding="utf-8") as f:
            f.write(default)
        return default
    return TEMPLATE_PATH.read_text(encoding="utf-8")

def _light_analysis(transcript: str) -> Tuple[str, str, List[str]]:
    """
    매우 얕은 휴리스틱:
    - filler 단어 개수
    - 간단 문법 패턴 한두 개 치환 예시
    """
    text = transcript.strip()
    if not text:
        return "—", "—", ["Say one full sentence next time."]

    lower = text.lower()
    fillers = {"um", "uh", "like", "you know", "kind of"}
    filler_hits = sum(lower.count(w) for w in fillers)

    example_before = "I am go to the library."
    example_after = "I'm going to the library."

    tips = []
    if filler_hits > 0:
        tips.append("Replace fillers with a short pause (2 beats).")
    tips.append("Keep sentences short (≤ 12 words) for clarity.")
    tips.append("Stress content words; de-stress function words.")
    return example_before, example_after, tips[:3]

def render_feedback_template(
    template: str,
    weights_norm: RubricWeights,
    overall: float | None,
    transcript: str
) -> str:
    example_before, example_after, tips = _light_analysis(transcript)
    mapping: Dict[str, Any] = {
        "overall": f"{overall:.1f}" if overall is not None else "—",
        "pron_w": f"{float(weights_norm.pronunciation):.2f}",
        "flu_w": f"{float(weights_norm.fluency):.2f}",
        "logic_w": f"{float(weights_norm.logic):.2f}",
        "example_before": example_before,
        "example_after": example_after,
        "tips": "- " + "\n- ".join(tips) if tips else "—",
    }
    try:
        return template.format(**mapping)
    except Exception:
        # 템플릿 오류 시 안전 출력
        safe = [
            f"Overall: {mapping['overall']}",
            f"Weights -> Pron {mapping['pron_w']}, Flu {mapping['flu_w']}, Logic {mapping['logic_w']}",
            f"Before: {mapping['example_before']}",
            f"After: {mapping['example_after']}",
            f"Tips:\n{mapping['tips']}",
        ]
        return "\n".join(safe)

def weighted_overall(scores: Dict[str, float], weights_norm: RubricWeights) -> float:
    # 점수 존재 시에만 계산
    p = float(scores.get("pronunciation", 0))
    f = float(scores.get("fluency", 0))
    l = float(scores.get("logic", 0))
    return p * float(weights_norm.pronunciation) + \
           f * float(weights_norm.fluency) + \
           l * float(weights_norm.logic)