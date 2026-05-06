# TOEIC Part 5/6/7 템플릿·난이도·오답 패턴·평가 기준 (v1)

- **파일 목적:** 파트5/6/7 문항 생성을 표준화하고, 난이도 제어/품질 평가/공정성 체크리스트를 일관되게 적용한다.
- **대상:** 생성 프롬프트 설계자, 검수자, 서버 측 품질 점검 엔드포인트.
- **버전:** v1 (2025-10-23)  
- **라이선스:** 팀 내부 사용

---

## 0) 공통 메타데이터 스키마

모든 문항은 아래 메타데이터 필드를 포함한다.

```json
{
  "id": "toeic_p5_20251023_0001",
  "part": 5,
  "skill": ["grammar", "vocabulary"],
  "topic": "office_policy",
  "difficulty": "M", // E/M/H
  "source": "gen_v1",
  "language": "en-US",
  "time_limit_sec": 60,
  "tags": ["verb_form", "collocation"],
  "fairness": {"bias_check": true, "notes": "neutral names"}
}
```

- `difficulty`: **E(쉬움) / M(보통) / H(어려움)**
- `tags`: 문법/의미 포인트(예: `verb_form`, `agreement`, `cohesion`, `tone`)
- `fairness.bias_check`: 문화/성별/직업 고정관념/차별 요소 배제 확인

---

## 1) 난이도 제어 가이드 (공통)

- **어휘 빈도**: E: 상위 3k 빈도 어휘 중심 / M: 3k~8k / H: 8k+ 또는 전문어 일부
- **문장 길이(Part 5)**: E: 8~14어 / M: 12~20어 / H: 18~28어
- **지문 길이(Part 6/7)**:
  - Part 6(각 문서): E: 90~130어 / M: 120~170어 / H: 160~220어 (빈칸 3~4개)
  - Part 7(단일): E: 120~180어 / M: 160~240어 / H: 220~320어
- **문법/담화 장치 복잡도**: E: 시제/전치사/기본품사 / M: 병렬/분사/관계사 / H: 가정법/도치/담화표지/암시적 추론
- **오답 난도**: E: 품사/시제 기본 대비 / M: 유사 의미·형태 / H: 관용·담화 기능 충돌, 함정(negation, scope, reference)

---

## 2) 오답 패턴 카탈로그 (Distractor Catalog)

**코드 체계:**
- `GRM-AGR`(수일치), `GRM-TNS`(시제), `GRM-POS`(품사), `GRM-PRP`(전치사), `GRM-ART`(관사)
- `LEX-COL`(연어 오류), `LEX-NEAR`(유사어 혼동), `LEX-IDM`(관용 표현)
- `COH-REF`(지시/참조 오류), `COH-LGC`(논리 연결 부적합), `COH-ORG`(문단 전개 불일치)
- `PRG-TONE`(문서 톤 부적합), `PRG-PURP`(문서 목적 불일치)

**설계 원칙**
1) 정답과 **한 차원만** 다르게: 품사/시제/의미/담화 기능 중 하나를 틀리게.
2) **과도한 함정 금지**: 모국어 화자도 오답률 60% 이상 유발하는 함정 배제.
3) **중복 정답 금지**: 정답 후보 1개만.
4) **표면적 힌트 방지**: 길이/철자 패턴으로 정답 유추 불가하도록.

---

## 3) 공정성·다양성 원칙

- **중립적 맥락**: 인명/지명은 다양한 문화권 예시를 섞고, 직군/성별의 고정관념 회피.
- **접근성**: 지문에 불필요한 문화 자본(특정 지역만 이해 가능한 속어/관습) 의존 금지.
- **톤**: 광고·공지·이메일 등 장르 톤을 유지하되, 차별/배제 표현 배제.
- **수정 지표**: `fairness.bias_check=true` + 검수 노트 필수.

---

## 4) Part 5 (문장 빈칸 채우기)

### 4.1 템플릿 형태

```
[Sentence with one blank ______ ]
Options: (A) ... (B) ... (C) ... (D) ...
Focus: grammar|vocabulary|collocation|logic
Difficulty: E|M|H
Tags: [ ... ]
```

### 4.2 템플릿 레시피

- **동사형 선택(시제/수동)** — Tags: `verb_form`, `tense`
  - 제약: 주어·부사 힌트 삽입(빈도부사, 시간부사구)
  - 오답: `GRM-TNS`, `GRM-AGR`
- **품사 선택(명사/형용사/부사)** — Tags: `part_of_speech`
  - 제약: 수식 대상 명확, 중의성 최소화
  - 오답: `GRM-POS`, `LEX-NEAR`
- **연어/관용** — Tags: `collocation`
  - 제약: 비문학적 비즈니스 맥락에서 자연스러움
  - 오답: `LEX-COL`

### 4.3 예시(샘플)

```
Employees are encouraged to ______ their ID badges at all times within the facility.
(A) wear  (B) wearing  (C) wore  (D) wears
Answer: (A)
Rationale: 동사원형 필요; 목적어 앞에서 ‘encouraged to + V’. 시제·수일치 충돌 오답 제공.
Difficulty: E  Tags: [verb_form, collocation]
```

---

## 5) Part 6 (문서 빈칸 채우기)

### 5.1 템플릿 구조

- 장르: 이메일 / 공지 / 메모 / 안내문
- 빈칸 수: 3~4개, 위치는 **문서 기능 전개** 상 핵심 지점(도입·전환·마감)
- 보기 형식: 각 빈칸당 (A)~(D) 4지 선다

### 5.2 레시피 & 제약

- **담화 연결(전환/대조/원인-결과)** — Tags: `cohesion`, `transition`
  - 오답: `COH-LGC`
- **문서 톤/형식(인사/요청/감사/서명)** — Tags: `tone`, `register`
  - 오답: `PRG-TONE`
- **어휘·문법 혼합** — Tags: `collocation`, `tense`, `reference`
  - 오답: `LEX-COL`, `GRM-TNS`, `COH-REF`

### 5.3 예시(샘플)

```
Subject: Maintenance Schedule
Hello team,
The elevator will be serviced this Friday from 9 a.m. to noon. ______ (1)
During this time, please use the stairs and allow extra time for deliveries. ______ (2)
We appreciate your patience and cooperation. ______ (3)
— Facilities Office

(1) (A) As a result, it remains fully operational. (B) Therefore, access will be limited.
    (C) Meanwhile, it was installed last year.       (D) For example, technicians arrive monthly.
(2) (A) Feel free to ignore the posted signs. (B) Note that safety guidelines will be in place.
    (C) The parking lot is open overnight.  (D) The cafeteria changed its menu.
(3) (A) Please let us know if you have concerns. (B) We canceled all future maintenance.
    (C) The building will be demolished.          (D) Everyone must relocate permanently.
Answers: (1) B  (2) B  (3) A
Rationale: 담화 연결·톤 적합성.
Difficulty: M  Tags: [cohesion, tone]
```

---

## 6) Part 7 (독해)

### 6.1 지문 유형

- 이메일/문자, 공지/브로셔, 기사/블로그, FAQ/웹페이지, 다중 지문(연계)

### 6.2 질문 유형 & 설계 포인트

- **Gist/Main idea** — 핵심 목적·주제
- **Detail** — 특정 사실(날짜/숫자/조건)
- **Inference** — 암시·관계 추론(지시어/담화 표지)
- **Vocab-in-context** — 문맥상 의미

**난이도 제어:**
- E: 명시적 단서, 단일 문장 근거
- M: 단서 분산, 간단 추론
- H: 대조/암시/다문서 교차 근거, 함의 추론

### 6.3 예시(단일 지문, 2문항)

```
[Notice]
Starting next Monday, the Riverside Gym will introduce a reservation system for group classes. Members can book up to two classes per week using the mobile app. Walk-ins will be allowed only if there are remaining spots five minutes before the class begins.

Q1. What is the main purpose of the notice?
(A) To announce a new booking policy  (B) To promote a new mobile app
(C) To introduce a new trainer         (D) To reduce the number of classes
Answer: (A)  Type: Gist  Difficulty: E

Q2. When may walk-ins attend a class?
(A) Any time on weekdays  (B) Only after a class ends
(C) If spots remain five minutes before it begins  (D) Only with staff approval
Answer: (C)  Type: Detail  Difficulty: E
```

---

## 7) 검수 루브릭 (생성 품질 평가)

**지표(5점 척도):**
1) **정답 타당성**: 근거로 1개 정답만 도출됨
2) **오답 품질**: 틀릴 만하지만 그럴듯, 중복정답/무의미 없음
3) **난이도 일치**: 길이/어휘/논리 복잡도 가이드 부합
4) **공정성/접근성**: 편향·배제 표현 없음, 문화 과의존 최소화
5) **언어 품질**: 자연스러운 비즈니스/일상 영어, 오류 없음

**통과 기준:** 총점 **≥ 21/25** 또는 핵심 지표(1,2,4) 모두 **≥4**.

**체크리스트(Yes/No):**
- 단일 정답?  
- 오답 3개 모두 카탈로그 코드로 설명 가능?  
- 난이도 표와 일치?  
- 편향 표현·문화 과의존 없음?  
- 문법/맞춤법 오류 없음?

---

## 8) 자동 점검 규칙 (서버 /toeic/eval 에서 활용)

- 구조 점검: 옵션 4개, 중복 없음, `answer_index` 유효
- 텍스트 점검(휴리스틱):
  - Part 5: 문장 길이 범위 확인
  - Part 6/7: 지문/문항 길이 범위, 금지 패턴(과도한 고유명사, 모호한 지시어 남용)
- 공정성 플래그: 특정 집단·속성 언급 시 수동 검수 필요 표시
- 결과: `passed`/`score(0~1)`/`reasons[]`

---

## 9) 산출물 포맷(제출 예)

```json
{
  "meta": {"part":5, "difficulty":"M", "tags":["verb_form","collocation"], "topic":"workplace"},
  "stem": "Employees are encouraged to ______ their ID badges at all times within the facility.",
  "options": ["wear", "wearing", "wore", "wears"],
  "answer_index": 0,
  "rationale": "encourage + to + V; present simple collocation 'wear ID badge'"
}
```

---

## 10) 생성 프롬프트 지침(요약)

- 템플릿·난이도·오답 카탈로그를 엄수해 문항을 만든다.
- 각 문항에 `meta`, `stem`, `options`, `answer_index`, `rationale`를 포함.
- 지문/문항 길이·어휘·담화 복잡도를 난이도와 일치시킨다.
- 공정성 체크리스트를 모두 통과하도록 생성한다.

---

## 11) Appendices

### A) 오답 코드 예시 테이블

| Code | 설명 | 예시 요약 |
|---|---|---|
| GRM-AGR | 수일치 오류 | 단수주어에 복수동사 |
| GRM-TNS | 시제 오류 | 과거 맥락에 현재완료 등 |
| GRM-POS | 품사 오류 | 형용사/부사 혼동 |
| LEX-COL | 연어 오류 | *do a decision* 등 |
| COH-LGC | 논리 연결 부적합 | 역접이 필요한 자리에 예시표지 |
| PRG-TONE | 문서 톤 부적합 | 안내문에서 과도한 구어체 |

### B) 샘플 세트(각 파트 1문항)

- 문서 본문 및 해설은 상단 섹션 예시 참조.
