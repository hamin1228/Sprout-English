# 파일: english_ai/server/app/toeic.py
# TOEIC Part 5 문항 생성/채점 모듈
#
# 무엇을 하는가
# - 템플릿 뱅크(PART5_BANK)에서 난이도 조건에 맞는 문항 템플릿을 선택
# - 보기를 무작위로 섞어 정답 위치를 매번 다르게 구성
# - 사용자의 응답을 채점하고 정답률 및 간단한 990 환산 점수를 계산
#
# 설계 노트(초보용)
# - 템플릿 항목 구조: (규칙키, 난이도, 지문템플릿, 정답토큰, 오답패턴리스트)
# - 지문템플릿의 '___'가 빈칸 위치이며, distractor(오답)는 자주 헷갈리는 형태로 구성
# - 난수 시드를 주면(shuffle 고정) 재현 가능한 결과를 얻을 수 있음
from __future__ import annotations

import random
from typing import Dict, List, Tuple
from app.schemas import ToeicQuestion, GenerateRequest, GenerateResponse, GradeRequest, GradeResponse, GradeItemResult, ScoreResponse

# ===== 템플릿 & 규칙 뱅크 (Part 5) =====
# 아래 PART5_BANK는 5지선다 빈칸 문제 템플릿 모음입니다.
# 각 항목 형식: (규칙키, 난이도, 지문템플릿, 정답토큰, 오답패턴리스트)
# 지문템플릿의 '___' 위치가 빈칸이며, distractor(오답)들은 자주 헷갈리는 형태로 구성합니다.
# 각 항목: (규칙키, 난이도, 지문템플릿, 정답토큰, 오답패턴)
# 지문템플릿 안의 ___ 가 빈칸
PART5_BANK = [
    (
        "sv_agreement", "easy",
        "The number of attendees ___ expected to increase after lunch.",
        "is",
        ["are", "be", "been"]
    ),
    (
        "verb_tense", "easy",
        "Our team ___ the quarterly report by next Friday.",
        "will submit",
        ["submits", "submitted", "is submitting"]
    ),
    (
        "word_form", "medium",
        "The manager gave a very ___ explanation of the policy changes.",
        "clear",
        ["clearly", "clarity", "clearer"]
    ),
    (
        "preposition", "medium",
        "Please send the finalized contract ___ email by noon.",
        "by",
        ["on", "in", "with"]
    ),
    (
        "article", "medium",
        "___ important update will be announced at 2 p.m.",
        "An",
        ["A", "The", "No article"]
    ),
    (
        "collocation", "hard",
        "The company is seeking to ___ costs without reducing quality.",
        "cut",
        ["slice", "drop", "slice down"]
    ),
    (
        "conditional", "hard",
        "If the supplier had informed us earlier, we ___ a different carrier.",
        "would have chosen",
        ["would choose", "chose", "had chosen"]
    ),
]

# 난이도 필터 매핑표
# - 사용자가 고른 difficulty 값에 따라 허용되는 난이도 집합을 결정합니다.
# - 예: 'hard' → {'medium','hard'}, 'mixed' → {'easy','medium','hard'}
# 사용자가 고른 난이도에 따라 포함할 난이도 범위를 정의합니다.
# 예) 'medium'을 고르면 easy+medium만 포함, 'hard'를 고르면 medium+hard만 포함.
# 'mixed'는 모든 난이도를 허용합니다.
DIFF_FILTER = {
    "easy": {"easy"},
    "medium": {"easy", "medium"},
    "hard": {"medium", "hard"},
    "mixed": {"easy", "medium", "hard"},
}

# 한 문항(ToeicQuestion) 생성기
# - 입력: stem(지문), correct(정답), distractors(오답들), rule(규칙키), difficulty, rng
# - 처리: 보기(A~D) 셔플 → 정답 레터 기록 → 간단 해설 생성
# - 출력: ToeicQuestion(stem, choices, answer, explanation, difficulty, skills, distractor_types)
def _build_item(stem: str, correct: str, distractors: List[str], rule: str, difficulty: str, rng: random.Random) -> ToeicQuestion:
    # 보기 라벨 고정(A~D)
    letters = ["A", "B", "C", "D"]

    # 보기 후보 = 오답 리스트 + 정답 1개
    all_opts = distractors + [correct]

    # 보기 순서 무작위 섞기 → 정답의 위치가 매번 달라짐
    rng.shuffle(all_opts)

    # letter(키) → 보기 텍스트(값) 매핑을 만든다
    mapping: Dict[str, str] = {}
    correct_letter = None  # 정답이 몇 번 보기에 들어갔는지 기록(A/B/C/D)

    # 최대 4개 보기만 채택(A~D)
    for i, text in enumerate(all_opts[:4]):
        letter = letters[i]
        mapping[letter] = text  # 예: 'A' → "is"
        if text == correct:
            correct_letter = letter  # 정답 레터 기억하기

    # 규칙 키를 바탕으로 간단 해설 문자열 만들기
    explanation = _make_explanation(rule, correct, distractors)

    # ToeicQuestion 데이터 모델 인스턴스를 반환
    return ToeicQuestion(
        stem=stem,
        choices=mapping,
        answer=correct_letter,  # type: ignore
        explanation=explanation,
        difficulty=difficulty,
        skills=[rule],
        distractor_types=[f"{rule}_trap"]
    )


# 해설 문자열 생성기
# - 규칙 키에 맞는 기본 설명을 고르고, 정답/오답 정보를 덧붙여 반환
# - 학습 피드백 강화를 위해 자주 틀리는 보기 목록을 함께 표기
def _make_explanation(rule: str, correct: str, distractors: List[str]) -> str:
    base = {
        "sv_agreement": "주어-동사 수일치 규칙. 단수 주어에는 단수 동사형이 와야 합니다.",
        "verb_tense": "시제 일치. 시점(‘by next Friday’)에 맞는 미래 시제가 적절합니다.",
        "word_form": "품사 선택. 형용사 자리이므로 형용사 형태가 와야 합니다.",
        "preposition": "전치사 용법. 전달 수단에는 ‘by’가 자연스러운 관용 표현입니다.",
        "article": "관사 선택. 모음 발음으로 시작하는 단어 앞에는 보통 ‘An’을 씁니다.",
        "collocation": "연어(관용결합). 비용 절감은 ‘cut costs’가 자연스러운 표현입니다.",
        "conditional": "가정법 과거완료. if+had p.p., 결과절은 would have p.p. 구조입니다.",
    }.get(rule, "해설")

    # (정답/오답) 정보를 함께 제공하여 학습 피드백을 강화
    return f"{base} (정답: {correct}; 자주 틀리는 보기: {', '.join(distractors)})"


# 요청에 따른 Part 5 세트 생성(안전 버전)
# 처리 단계
# 1) 난수 시드 고정 → 재현 가능한 셔플
# 2) DIFF_FILTER에 따라 템플릿 후보 필터링
# 3) 동일 stem(문장 템플릿) 중복 제거
# 4) 섞은 뒤 필요한 개수만 선택(take=min(requested, available))
# 5) _build_item으로 각 문항 생성
# 6) 메타 정보 구성(요청/반환 개수, 시드, 참고 노트 등)
# 안전장치: while 루프 미사용(무한 루프 방지), 요청 수가 가용 수를 초과하면 가능한 만큼만 반환
def generate_toeic_set(req: GenerateRequest) -> GenerateResponse:
    # 1) 난수 시드 세팅(동일 입력이면 동일 셔플 결과를 얻기 위함)
    rng = random.Random(req.seed)

    # 2) 요청 난이도에 해당하는 후보만 추출
    candidates = [x for x in PART5_BANK if x[1] in DIFF_FILTER[req.difficulty]]

    # 3) stem(문장 템플릿) 기준으로 고유화: 같은 문장은 한 번만 쓰기
    by_stem: Dict[str, tuple] = {}
    for tpl in candidates:
        rule, diff, stem, correct, distractors = tpl
        if stem not in by_stem:
            by_stem[stem] = tpl

    # 4) 모든 stem을 섞고, 필요한 개수만큼 선택
    stems = list(by_stem.keys())
    rng.shuffle(stems)

    requested = req.count
    available = len(stems)
    take = min(requested, available)  # 요청 수를 초과하지 않도록 제한
    picked_stems = stems[:take]

    # 5) 선택된 stem으로 문항 생성
    items: List[ToeicQuestion] = []
    for stem in picked_stems:
        rule, diff, stem, correct, distractors = by_stem[stem]
        items.append(_build_item(stem, correct, distractors, rule, diff, rng))

    # 6) 메타 정보(요청/반환/가능 최대치 안내)
    meta = {
        "part": str(req.part),
        "difficulty": req.difficulty,
        "seed": str(req.seed),
        "requested_count": str(requested),
        "returned_count": str(len(items)),
    }
    if requested > available:
        meta["note"] = "요청 개수가 난이도 템플릿 수를 초과하여 가능한 만큼만 반환했습니다."
        meta["max_available_for_difficulty"] = str(available)

    return GenerateResponse(items=items, meta=meta)


# 보기 레터 정규화 유틸
# - 입력 문자열을 트림하고 대문자로 변환 → {'A','B','C','D'} 중 하나만 통과
# - 유효하지 않으면 None 반환(미응답/오타 처리)
def _normalize_letter(s: str | None) -> str | None:
    if s is None:
        return None
    s = s.strip().upper()
    return s if s in {"A", "B", "C", "D"} else None


# 간단 990 환산 점수 매핑(정보 목적)
# - 0.00 → 0, 1.00 → 990 선형 매핑
# - 중간 값은 10점 단위로 반올림, 실제 TOEIC 표와는 무관
def _scaled_990(percent: float) -> int:
    # 간단 선형 매핑(정보 목적) : 0.00 -> 0, 1.00 -> 990
    scaled = int(round(percent * 99)) * 10
    return max(0, min(990, scaled))


# 채점기: 사용자 응답을 바탕으로 총점/문항별 결과 산출
# 처리 단계
# 1) 문항 ID → 문항 객체 매핑(qmap) 구성
# 2) 각 응답을 A/B/C/D로 정규화 → 정답 여부 판정
# 3) 정답 개수 누적 → 정답률 계산
# 4) _scaled_990으로 안내용 점수 산출
# 5) GradeResponse(score, results) 반환
def grade_toeic_set(req: GradeRequest) -> GradeResponse:
    # 1) 문항 ID → 문항 객체 매핑
    qmap = {q.id: q for q in req.questions}

    results: List[GradeItemResult] = []
    correct = 0

    # 2) 사용자 응답을 순회하며 채점
    for qid, q in qmap.items():
        user_raw = req.responses.get(qid)
        user_norm = _normalize_letter(user_raw)
        is_correct = (user_norm == q.answer)
        if is_correct:
            correct += 1

        # 문항별 결과(정답/오답/해설)를 기록
        results.append(GradeItemResult(
            id=qid,
            user_answer=user_norm,
            correct_answer=q.answer,
            is_correct=is_correct,
            explanation=q.explanation
        ))

    # 3) 총점/정답률/환산점수 계산
    total = len(qmap)
    percent = (correct / total) if total else 0.0
    score = ScoreResponse(
        total=total,
        correct=correct,
        percent=percent,
        scaled_990=_scaled_990(percent)
    )

    # 4) 최종 응답 객체 반환
    return GradeResponse(score=score, results=results)