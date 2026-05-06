# 스크린샷 촬영 가이드

이 폴더에 앱 스크린샷을 추가해 README에 연결하세요.

## 권장 촬영 환경

- **해상도**: 1080×2340 (FHD+) 이상
- **기기**: Pixel 7a 에뮬레이터 또는 실물 Android 기기
- **형식**: PNG (고화질) 또는 WebP (파일 크기 최적화)
- **비율**: 9:19.5 (일반 스마트폰 비율)

---

## 필요한 스크린샷 목록

| 파일명 | 화면 | 촬영 포인트 |
|--------|------|------------|
| `01_home.png` | 홈 화면 | 학습 현황 카드, 기능 메뉴 그리드 |
| `02_free_talk.png` | AI 프리토킹 | 마이크 버튼, 대화 버블, 파형 |
| `03_ai_tutor.png` | AI 튜터 채팅 | 채팅 UI, 교정 피드백 말풍선 |
| `04_roleplay_select.png` | 롤플레이 시나리오 선택 | 시나리오 카드 목록 (카페/공항/회의 등) |
| `05_roleplay_session.png` | 롤플레이 진행 중 | 역할극 배경 이미지, 대화 자막 |
| `06_speaking_result.png` | 스피킹 평가 결과 | WPM·침묵비율·유창성 점수 카드 |
| `07_writing_diff.png` | 글쓰기 교정 결과 | 원문 vs 교정본 diff 뷰 |
| `08_toeic_writing.png` | TOEIC Writing | 이미지 문제 + 답변 입력 화면 |
| `09_vocab_review.png` | 단어 복습 | SRS 카드 플립 UI |
| `10_statistics.png` | 학습 통계 | 연속 학습일, 점수 추이 그래프 |

---

## README에 추가하는 방법

스크린샷 파일을 이 폴더에 저장한 뒤, README.md의 스크린샷 섹션에 아래처럼 추가하세요:

```markdown
## 스크린샷

<p float="left">
  <img src="docs/screenshots/01_home.png" width="200" alt="홈 화면" />
  <img src="docs/screenshots/02_free_talk.png" width="200" alt="AI 프리토킹" />
  <img src="docs/screenshots/03_ai_tutor.png" width="200" alt="AI 튜터 채팅" />
  <img src="docs/screenshots/04_roleplay_select.png" width="200" alt="롤플레이 선택" />
</p>

<p float="left">
  <img src="docs/screenshots/05_roleplay_session.png" width="200" alt="롤플레이 진행" />
  <img src="docs/screenshots/06_speaking_result.png" width="200" alt="스피킹 평가" />
  <img src="docs/screenshots/07_writing_diff.png" width="200" alt="글쓰기 교정" />
  <img src="docs/screenshots/08_toeic_writing.png" width="200" alt="TOEIC Writing" />
</p>

<p float="left">
  <img src="docs/screenshots/09_vocab_review.png" width="200" alt="단어 복습" />
  <img src="docs/screenshots/10_statistics.png" width="200" alt="학습 통계" />
</p>
```

---

## Android 에뮬레이터에서 스크린샷 찍는 방법

```bash
# Android Studio 사이드바의 카메라 아이콘 클릭
# 또는 adb 명령어로 저장
adb exec-out screencap -p > docs/screenshots/01_home.png
```

또는 Android Studio → Device Manager → 에뮬레이터 화면 우클릭 → Take Screenshot

---

## 시연 영상 (선택)

시연 영상이 있다면 README에 아래처럼 추가하세요:

```markdown
## 시연 영상

[![Sprout English 시연](https://img.youtube.com/vi/YOUR_VIDEO_ID/0.jpg)](https://www.youtube.com/watch?v=YOUR_VIDEO_ID)
```
