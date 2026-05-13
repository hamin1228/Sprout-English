# 파일: schemas_merged.py
# 정책: 충돌 시 base 우선, import 중복 제거

from __future__ import annotations

from typing import List, Optional, Dict, Any, Literal
from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from uuid import uuid4


# ── Auth Schemas ──────────────────────────────────────────────────────────────

class UserCreate(BaseModel):
    email: str = Field(..., min_length=3, max_length=255)
    password: str = Field(..., min_length=8, max_length=128)
    nickname: Optional[str] = Field(default=None, max_length=64)


class UserLogin(BaseModel):
    email: str
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    public_id: str
    email: str
    nickname: Optional[str] = None
    is_active: bool
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserOut


class RefreshTokenRequest(BaseModel):
    refresh_token: str

# 말하기 점수 산출 요청 모델
# - transcript: 전체 발화 텍스트
# - duration_ms / silence_ms: 총 길이/무음 길이(ms)
# - store: 서버 저장 여부(기본 True)
# 필드 요약: user_id(str), session_id(Optional[str]), transcript(str), duration_ms(int≥1), silence_ms(Optional[int≥0])
class ScoreRequest(BaseModel):
    user_id: str
    session_id: Optional[str] = None
    transcript: str
    duration_ms: int = Field(ge=1)
    silence_ms: Optional[int] = Field(default=None, ge=0)
    store: bool = True

# 말하기 메트릭 원자료
# - words: 단어 수
# - wpm: 분당 단어 수(words per minute)
# - filler_count: 필러(uh, um 등) 개수
# - silence_ratio: 무음 비율(0.0~1.0)
class Metrics(BaseModel):
    words: int
    wpm: float
    filler_count: int
    silence_ratio: float

# 세부 점수 구성 요소
# - wpm_score: 말하기 속도 점수(권장 범위에 근접할수록 높음)
# - filler_penalty: 필러 사용 감점(많을수록 감점↑)
# - silence_penalty: 무음 비율 감점(길수록 감점↑)
# - rule_score: 규칙 기반 점수(간단 규칙 평가)
# - gpt_score: LLM 기반 총평 점수
class SubScores(BaseModel):
    wpm_score: float
    filler_penalty: float
    silence_penalty: float
    rule_score: float
    gpt_score: float

# 말하기 평가 응답(요약)
# - total_score: 최종 점수(0~100 가정)
# - metrics: 원자료 메트릭
# - subscores: 세부 점수(가중치 합성 전후 판단용)
# - feedback: 항목별 코멘트/권장 액션 딕셔너리
class SpeakingScoreResponse(BaseModel):
    total_score: float
    metrics: Metrics
    subscores: SubScores
    feedback: Dict[str, Any]

# DB에서 읽어오는 말하기 점수 레코드(상세)
# - from_attributes=True 로 ORM 객체에서 직렬화 지원
class SpeakingScoreRead(BaseModel):
    id: int
    user_id: str
    session_id: Optional[str]
    transcript: str
    duration_ms: int
    words: int
    wpm: float
    filler_count: int
    silence_ratio: float
    rule_score: float
    gpt_score: float
    total_score: float
    feedback: Dict[str, Any]
    created_at: datetime

    # Pydantic 설정: ORM 객체 직렬화 지원
    class Config:
        from_attributes = True

# 말하기 점수 목록 응답
# - items: 상세 레코드 배열
# - total: 전체 개수(서버가 알고 있는 총 카운트)
class SpeakingScoreList(BaseModel):
    total: int
    items: List[SpeakingScoreOut]

# 수정 제안 항목(Edit)
# - kind: replace/insert/delete/comment 중 하나
# - start/end: 텍스트 내 인덱스(0-based, end-exclusive)
# - replacement: 교체 텍스트(필요 시)
# - reason/category/severity: 교정 이유/분류/강도
class Edit(BaseModel):
    kind: Literal['replace', 'insert', 'delete', 'comment']
    start: int = Field(ge=0)
    end: int = Field(ge=0)
    replacement: Optional[str] = None
    reason: str
    category: Literal['grammar', 'word_choice', 'style', 'punctuation', 'fluency', 'register', 'other'] = 'other'
    severity: Literal['minor', 'moderate', 'major'] = 'minor'

# 쓰기 평가 요청
# - text: 평가 대상 원문(필수)
# - level/task/audience/style: 컨텍스트(선택)
# - user_id/save: 저장 옵션
class WritingEvalRequest(BaseModel):
    text: str = Field(min_length=1)
    level: Optional[str] = Field(default=None, description='CEFR 등급 등 (A2/B1/B2...)')
    task: Optional[str] = Field(default=None, description='에세이/이메일/요약 등')
    audience: Optional[str] = None
    style: Optional[str] = None
    user_id: Optional[str] = None
    save: bool = False

# 쓰기 평가 응답
# - normalized_text/edits/checklist/warnings/score 포함
# - guidance_version/model_name: 평가 규칙/모델 식별자
# - record_id: save=true 일 때 생성된 레코드 id
class WritingEvalResponse(BaseModel):
    normalized_text: str
    edits: List[Edit]
    checklist: List[str]
    warnings: List[str]
    score: int = Field(ge=0, le=100)
    guidance_version: GuidanceVersion = 'writing_eval_v1_20251011'
    model_name: str = 'gpt-5-nano'
    record_id: Optional[int] = None

# 쓰기 점수 직접 생성 요청(LLM 비경유)
# - edits/checklist/warnings: 사전 계산값 사용
class CreateScoreRequest(BaseModel):
    user_id: Optional[str] = None
    input_text: str
    normalized_text: str
    edits: List[Edit]
    checklist: List[str]
    warnings: List[str]
    score: int = Field(ge=0, le=100)
    model_name: str = 'gpt-5-nano'
    guidance_version: GuidanceVersion = 'writing_eval_v1_20251011'
    notes: Optional[str] = None

# 쓰기 점수 응답(단건)
# - created_at/updated_at: ISO8601 문자열
# - is_deleted: soft delete 여부
class WritingScoreResponse(BaseModel):
    id: int
    user_id: Optional[str]
    input_text: str
    normalized_text: str
    edits: List[Edit]
    checklist: List[str]
    warnings: List[str]
    score: int
    model_name: str
    guidance_version: GuidanceVersion
    notes: Optional[str]
    created_at: str
    updated_at: str
    is_deleted: bool = False


ToeicWritingTaskType = Literal['picture', 'email', 'opinion']
ToeicWritingLevel = Literal['beginner', 'intermediate', 'advanced']


class ToeicWritingPromptResponse(BaseModel):
    prompt_id: str
    task_type: ToeicWritingTaskType
    title: str
    instructions: str
    time_limit_sec: int = Field(ge=60)
    recommended_words: int = Field(ge=1)
    required_points: List[str] = Field(default_factory=list)
    image_asset: Optional[str] = None
    source_text: Optional[str] = None
    keywords: Optional[List[List[str]]] = None


class ToeicRubricItem(BaseModel):
    label: str
    score: int = Field(ge=0)
    max_score: int = Field(ge=1)
    feedback: str


class ToeicWritingSubmission(BaseModel):
    text: Optional[str] = None
    sentences: List[str] = Field(default_factory=list)


class ToeicWritingEvalRequest(BaseModel):
    prompt_id: str
    task_type: ToeicWritingTaskType
    submission: ToeicWritingSubmission
    elapsed_sec: int = Field(default=0, ge=0)
    save: bool = False
    user_id: Optional[str] = None


class ToeicWritingEvalResponse(BaseModel):
    overall_score: int = Field(ge=0, le=100)
    rubric: List[ToeicRubricItem] = Field(default_factory=list)
    model_answer: str
    content_analysis: List[str] = Field(default_factory=list)
    grammar_feedback: List[str] = Field(default_factory=list)
    matched_points: List[str] = Field(default_factory=list)
    missing_points: List[str] = Field(default_factory=list)
    better_answer_tips: List[str] = Field(default_factory=list)
    record_id: Optional[int] = None

# 쓰기 점수 목록 응답(페이징)
# - next_offset: 다음 페이지 오프셋(없으면 None)
# - total: 전체 개수(선택)
class ListScoresResponse(BaseModel):
    items: list[WritingScoreResponse]
    next_offset: int | None = None
    total: int | None = None

# 쓰기 점수 일부 수정 요청
# - score/notes 만 부분 업데이트 지원
class UpdateScoreRequest(BaseModel):
    score: Optional[int] = Field(default=None, ge=0, le=100)
    notes: Optional[str] = None

# 평가 규칙 버전(문자 리터럴로 고정하여 타이핑 안정성 확보)
GuidanceVersion = Literal['writing_eval_v1_20251011']

# 객관식 보기 레터 타입(A/B/C/D)
ChoiceLetter = Literal["A", "B", "C", "D"]

# TOEIC 스타일 객관식 문항(Part 5)
# - stem: 빈칸 포함 문장(예: "The report ___ tomorrow.")
# - choices: 보기 딕셔너리 {'A': 'is', ...}
# - answer: 정답 레터('A'~'D')
# - explanation: 규칙/근거 설명
# - difficulty: 쉬움/중간/어려움
# - skills/distractor_types: 평가 스킬/오답 유형 태그
class ToeicQuestion(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    part: int = 5
    stem: str  # 지문(빈칸 포함 문장)
    choices: Dict[ChoiceLetter, str]  # 보기
    answer: ChoiceLetter  # 정답
    explanation: str  # 해설(규칙/근거)
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    skills: List[str] = []  # 예: ["sv_agreement", "verb_tense"]
    distractor_types: List[str] = []

# TOEIC 문제 생성 요청
# - count: 생성 개수(1~50)
# - part: 현재 5만 지원
# - difficulty: easy/medium/hard/mixed
# - seed: 셔플 재현용 시드
class GenerateRequest(BaseModel):
    count: int = Field(ge=1, le=50, default=5)
    part: int = 5  # 현재 5만 지원
    difficulty: Literal["easy", "medium", "hard", "mixed"] = "mixed"
    seed: Optional[int] = None

# TOEIC 문제 생성 응답
# - items: 생성된 문항 배열
# - meta: 부가 정보(요청 파라미터/노트 등)
class GenerateResponse(BaseModel):
    items: List[ToeicQuestion]
    meta: Dict[str, str] = {}

# 채점 결과(문항별)
# - user_answer: 사용자가 고른 보기 레터(None=미응답)
# - correct_answer: 정답 레터
# - is_correct: 정오표시
# - explanation: 해당 문항 해설
class GradeItemResult(BaseModel):
    id: str
    user_answer: Optional[ChoiceLetter] = None
    correct_answer: ChoiceLetter
    is_correct: bool
    explanation: str

# 공용 스코어 응답 모델(채점 요약)
# - total: 총 문항 수
# - correct: 정답 개수
# - percent: 정답 비율(0.0~1.0)
# - scaled_990: 안내용 990 환산 점수
class ScoreResponse(BaseModel):
    total: int
    correct: int
    percent: float  # 0.0 ~ 1.0
    scaled_990: int

# 채점 요청(서버 저장 없이 원본+응답 동봉)
# - questions: 출제된 문항 원본 배열
# - responses: {문항ID: 보기레터} (대소문자/공백 무시는 서버 로직에서 처리)
class GradeRequest(BaseModel):
    questions: List[ToeicQuestion]
    # {"문항ID": "A"|"B"|"C"|"D"} (대소문자/공백 무시)
    responses: Dict[str, str]

# 채점 응답(총점 + 문항별 결과)
class GradeResponse(BaseModel):
    score: ScoreResponse
    results: List[GradeItemResult]


# ===== Merged from schemas(7).py (non-conflicting symbols only; comments preserved) =====

# server/app/schemas.py
# [moved to file top] from __future__ import annotations
from typing import List, Optional, Literal, Dict, Any
from pydantic import BaseModel, Field

#
# 롤플레이 타입 정의
# - RoleplayState: 세션 상태 머신 단계(INIT/INTRO/DIALOGUE/REVIEW/ENDED)
# - Pace: 진행 속도 설정(slow/normal/fast)
#
RoleplayState = Literal["INIT", "INTRO", "DIALOGUE", "REVIEW", "ENDED"]
RoleplayDifficulty = Literal["beginner", "intermediate", "advanced"]
RoleplayInputSource = Literal["text", "voice"]
Pace = Literal["slow", "normal", "fast"]

#
# 롤플레이 메시지 단위
# - role: 발화 주체(system/user/assistant)
# - content: 메시지 텍스트
#
class RoleplayMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str

#
# 롤플레이 세션 상태 스냅샷
# - state: 현재 단계(RoleplayState)
# - turn_index: 현재 턴 번호(0-base)
# - goal/persona: 세션 목표/페르소나(옵션)
# - target_turns: 목표 턴 수(기본 12)
# - variables: 세션 진행에 사용하는 임의의 상태 값 딕셔너리
#
class RoleplaySessionState(BaseModel):
    state: RoleplayState = "INIT"
    turn_index: int = 0
    scenario_id: Optional[str] = None
    difficulty: Optional[RoleplayDifficulty] = None
    goal: Optional[str] = None
    persona: Optional[str] = None
    target_turns: int = 12
    stage_index: int = 0
    stage_status: str = "idle"
    completed_objectives: List[str] = Field(default_factory=list)
    redirect_count: int = 0
    is_complete: bool = False
    estimated_minutes: Optional[int] = None
    variables: Dict[str, Any] = Field(default_factory=dict)

#
# 롤플레이 생성 요청 페이로드
# - session_id: 이어서 생성할 세션 id(없으면 새로 시작)
# - user_input: 사용자의 최신 입력(없으면 초기 프롬프트로 간주)
# - goal/persona: 세션 목표/페르소나 덮어쓰기
# - pace: 진행 속도(slow/normal/fast)
# - target_turns: 목표 턴 수(옵션)
# - seed_history: 초기 히스토리(system/user/assistant 메시지 배열)
#
class RoleplayGenerateRequest(BaseModel):
    session_id: Optional[str] = None
    scenario_id: Optional[str] = None
    difficulty: Optional[RoleplayDifficulty] = None
    user_input: Optional[str] = None
    goal: Optional[str] = None
    persona: Optional[str] = None
    input_source: RoleplayInputSource = "text"
    pace: Pace = "normal"
    target_turns: Optional[int] = None
    seed_history: Optional[List[RoleplayMessage]] = None

#
# 스트리밍 전송용 텍스트 청크
# - index: 0부터 시작하는 순번
# - text: 부분 문자열
# - is_last: 마지막 청크 여부
#
class Chunk(BaseModel):
    index: int
    text: str
    is_last: bool

#
# 롤플레이 생성 응답
# - session_id/turn_index: 세션 식별자와 현재 턴
# - assistant_utterance: 완성된 응답 전체 텍스트
# - chunks: 스트리밍 청크 목록(선택적으로 사용)
# - state: 갱신된 세션 상태 스냅샷
# - meta: 기타 부가 정보
#
class RoleplayGenerateResponse(BaseModel):
    session_id: str
    turn_index: int
    assistant_utterance: str
    current_stage_title: Optional[str] = None
    current_objective_ko: Optional[str] = None
    hint_en: Optional[str] = None
    should_redirect: bool = False
    session_complete: bool = False
    tts_text: Optional[str] = None
    chunks: List[Chunk]
    state: RoleplaySessionState
    meta: Dict[str, Any] = Field(default_factory=dict)


class RoleplayStageSummary(BaseModel):
    id: str
    title: str
    objective_ko: str
    hint_en: str


class RoleplayCatalogItem(BaseModel):
    id: str
    difficulty: RoleplayDifficulty
    title: str
    subtitle: str
    summary_ko: str
    estimated_minutes: int
    background_asset: str
    ai_role: str
    user_goal_ko: str
    opening_line: str
    stages: List[RoleplayStageSummary]


class RoleplayCatalogResponse(BaseModel):
    items: List[RoleplayCatalogItem]


# 추가된 임포트(패턴 드릴/패러프레이즈용)
from typing import List, Literal, Optional


# 추가된 스키마 정의(패턴 드릴/패러프레이즈)
#
# [설명] Pattern Drill 요청 모델
#  - task: "generate" 또는 "score"
#  - pattern: 목표 패턴/규칙
#  - count/context: 문항 생성 옵션
#  - user_answer/reference_answers: 채점(score) 시 사용
#  - locale: 언어 태그(en/ko)
#  - tolerance: 합격 임계치(0~1)
class PatternDrillRequest(BaseModel):
    task: Literal["generate", "score"]
    pattern: str = Field(..., description="Target language pattern or rule")
    count: int = 5
    context: Optional[str] = None
    # For scoring
    user_answer: Optional[str] = None
    reference_answers: Optional[List[str]] = None
    locale: Literal["en", "ko"] = "en"
    tolerance: float = 0.70  # 0~1
#
# [설명] Pattern Drill 생성 응답
#  - items: [{"prompt": 질문, "answers":[허용 정답들]}]
class PatternDrillGenerateResponse(BaseModel):
    items: List[dict]
#
# [설명] Pattern Drill 채점 응답
#  - score: 유사도 점수(0~1)
#  - pass: 합격 여부(필드명은 pass_, alias="pass")
#  - reasons: 판정 사유 목록
#  - best_match: 가장 유사한 참조 정답
#  - used_tolerance: 사용한 임계치
class PatternDrillScoreResponse(BaseModel):
    score: float
    pass_: bool = Field(..., alias="pass")
    reasons: List[str]
    best_match: Optional[str] = None
    used_tolerance: float
#
# [설명] Paraphrase 요청 모델
#  - text: 원문
#  - tone: neutral/formal/casual/friendly/polite/academic/concise
#  - length: shorter/same/longer
#  - n: 후보 개수(1~5 권장)
class ParaphraseRequest(BaseModel):
    text: str
    tone: Literal["neutral","formal","casual","friendly","polite","academic","concise"] = "neutral"
    length: Literal["shorter","same","longer"] = "same"
    n: int = 3
#
# [설명] Paraphrase 응답 모델
#  - candidates: [{"text": 변환문, "tone": 톤, "length": 길이}] 목록
#  - meta: LLM 사용 여부/목업 여부 등 부가 메타데이터
class ParaphraseResponse(BaseModel):
    candidates: List[dict]
    meta: dict = {}


# [NEW-ONLY COMMENT]
# 아래부터 "이번 주 추가"된 스키마 정의입니다. (기존 코드에는 변경 없음)
# - Mistake/SRS: MistakeCreate, MistakeOut, ReviewIn, SRSItem
# - VectorStore: UpsertItem, UpsertReq, QueryReq

# [NEW] 오답 생성 요청 모델
# - index=True면 생성 시 벡터 인덱싱 수행, namespace 기본값 'mistakes'
class MistakeCreate(BaseModel):
    user_id: Optional[str] = None
    text: str
    correction: Optional[str] = None
    tags: Optional[str] = None
    difficulty: int = 2
    prompt_id: Optional[str] = None
    index: bool = True                 # 인덱싱 여부(기본 on)
    namespace: str = "mistakes"

# [NEW] 오답 단건 응답 모델
# - due_at: 현재 SRS 상태의 복습 예정 시각
class MistakeOut(BaseModel):
    id: int
    text: str
    correction: Optional[str] = None
    tags: Optional[str] = None
    due_at: datetime
    class Config: from_attributes = True

# [NEW] SRS 리뷰 입력 모델
# - quality: 0~5 (SM-2 유사 규칙에 사용)
class ReviewIn(BaseModel):
    mistake_id: int
    quality: int = Field(ge=0, le=5)

# [NEW] SRS 대기열 항목 모델
# - /srs/next 응답에서 사용
class SRSItem(BaseModel):
    id: int
    text: str
    correction: Optional[str] = None
    due_at: datetime

# [NEW] 벡터 인덱스 Upsert 항목
# - ref_id로 원본 식별 (예: 'mistake:{id}')
class UpsertItem(BaseModel):
    ref_id: str
    text: str
    meta: Optional[dict[str, Any]] = None

# [NEW] 벡터 인덱스 Upsert 요청
# - 동일 namespace 내에서 items 일괄 삽입/갱신
class UpsertReq(BaseModel):
    namespace: str
    items: List[UpsertItem]

# [NEW] 벡터 쿼리 요청
# - query 문자열을 임베딩하여 top_k 최근접 결과 반환
class QueryReq(BaseModel):
    namespace: str
    query: str
    top_k: int = 5


VocabGrade = Literal["again", "hard", "good", "easy"]
VocabLevel = Literal["beginner", "intermediate", "advanced"]
VocabDirection = Literal["word_to_meaning", "meaning_to_word"]


class VocabCardCreate(BaseModel):
    user_id: Optional[str] = None
    lemma: str = Field(min_length=1, max_length=128)
    meaning_ko: str = Field(min_length=1, max_length=255)
    example_en: Optional[str] = None
    difficulty: int = Field(default=2, ge=1, le=3)
    tags: Optional[str] = None
    pos: Optional[str] = None


class VocabCardUpdate(BaseModel):
    lemma: Optional[str] = Field(default=None, min_length=1, max_length=128)
    meaning_ko: Optional[str] = Field(default=None, min_length=1, max_length=255)
    example_en: Optional[str] = None
    difficulty: Optional[int] = Field(default=None, ge=1, le=3)
    tags: Optional[str] = None
    pos: Optional[str] = None


class VocabCardOut(BaseModel):
    id: int
    user_id: Optional[str] = None
    lemma: str
    meaning_ko: str
    example_en: Optional[str] = None
    difficulty: int
    source: str
    tags: Optional[str] = None
    pos: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class VocabImportRequest(BaseModel):
    level: Optional[VocabLevel] = None
    category: Optional[str] = None
    limit: int = Field(default=50, ge=1, le=500)
    user_id: Optional[str] = None


class VocabImportResult(BaseModel):
    imported: int
    skipped: int
    total_candidates: int


class VocabSRSItem(BaseModel):
    card_id: int
    lemma: str
    meaning_ko: str
    example_en: Optional[str] = None
    difficulty: int
    due_at: datetime
    direction: VocabDirection


class VocabReviewIn(BaseModel):
    card_id: int
    grade: VocabGrade


class VocabReviewOut(BaseModel):
    card_id: int
    grade: VocabGrade
    quality: int
    next_due_at: datetime
    ease: float
    interval_days: float
    reps: int


class VocabMCQItem(BaseModel):
    card_id: int
    level: VocabLevel
    direction: VocabDirection
    question_text: str
    choices: List[str]
    answer_index: int = Field(ge=0, le=3)
