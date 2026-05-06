# [설명] 의미 보존/유사도 평가 유틸 (이번 주 추가)
#  - 역할: Pattern Drill 채점 등에서 사용자 답과 참조 정답 간 의미 유사도를 계산
#  - 구성: _normalize(정규화) → similarity(유사도 계산) → score_answer(최댓값/참조 반환)
#  - 범위: 영어 기준(간단한 stopword 세트 사용), 출력 범위 0.0~1.0
import re
import difflib
from typing import List, Tuple

# [설명] 토큰화/불용어 설정
#  - _WORD: 영문 단어/축약형 토큰 정규식
#  - EN_STOP: 간단한 영어 불용어 집합(관사/전치사/조동사/대명사 등)

_WORD = re.compile(r"[A-Za-z']+")

EN_STOP = {
    "a","an","the","to","for","of","in","on","at","and","or","but","is","are","am","be",
    "was","were","been","have","has","had","do","does","did","i","you","he","she","we","they"
}

# [설명] _normalize
#  - 입력 문자열에서 영문 토큰만 추출 → 소문자화 → 불용어 제거
#  - 반환: 의미 비교에 사용할 토큰 리스트
def _normalize(s: str) -> List[str]:
    toks = [t.lower() for t in _WORD.findall(s)]
    return [t for t in toks if t not in EN_STOP]

# [설명] similarity
#  - 토큰 Jaccard 유사도와 difflib(문자 시퀀스 유사도)를 0.45/0.55로 결합
#  - 짧은 문장/오타에 다소 강인하며, 0.0~1.0 범위를 반환
def similarity(a: str, b: str) -> float:
    # [설명] 유사도: 토큰 Jaccard(0~1)와 문자 기반 비율을 가중합(0.45/0.55)
    ta, tb = set(_normalize(a)), set(_normalize(b))
    jacc = len(ta & tb) / max(1, len(ta | tb))
    ratio = difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio()
    return 0.45 * jacc + 0.55 * ratio

# [설명] score_answer
#  - refs 각 항목과의 similarity를 계산하여 가장 큰 점수와 해당 참조 문장을 반환
#  - refs가 비어 있으면 (0.0, "")를 반환
#  - 사용처: /pattern/drill 채점(task="score")
def score_answer(user: str, refs: List[str]) -> Tuple[float, str]:
    scores = [(similarity(user, r), r) for r in refs]
    scores.sort(key=lambda x: x[0], reverse=True)
    return scores[0] if scores else (0.0, "")