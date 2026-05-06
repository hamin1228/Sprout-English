import os, json
from typing import Optional, Dict, Any
import httpx

# [설명] LLM 호출 유틸 (이번 주 추가)
#  - 역할: OpenAI Chat Completions를 호출해 JSON 응답을 받고, 실패 시 안전한 폴백을 제공
#  - 환경변수:
#      · LLM_MODE: "openai" | "mock" (기본 mock)
#      · LLM_MODEL: 사용 모델명 (기본: gpt-5-nano)
#      · OPENAI_API_KEY: OpenAI API 키
LLM_MODE = os.getenv("LLM_MODE", "mock").lower()  # 사용 모드: "openai" | "mock" (기본 mock)
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-5-nano")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# [설명] 저수준 OpenAI 호출 함수
#  - 입력: messages, json_only, temperature
#  - 동작: json_only=True이면 response_format=json_object로 JSON 응답을 요청
#  - 출력: OpenAI 응답의 message.content(raw string)
def _openai_chat(messages: list, json_only: bool = True, temperature: float = 0.3) -> str:
    url = "https://api.openai.com/v1/chat/completions"
    headers = {"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type":"application/json"}
    body = {
        "model": LLM_MODEL,
        "messages": messages,
        "temperature": temperature,
    }
    # [설명] 가능하면 JSON 모드(response_format=json_object)로 요청하고, 실패 시 일반 텍스트로 폴백
    if json_only:
        body["response_format"] = {"type": "json_object"}
    with httpx.Client(timeout=60) as client:
        r = client.post(url, headers=headers, json=body)
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"]

# [설명] JSON 응답 헬퍼
#  - OpenAI 사용 가능 시: JSON 파싱을 시도하고 실패하면 비-JSON 응답에서 중괄호 영역을 재파싱
#  - 사용 불가/실패 시: None 반환 → 상위(엔드포인트)에서 목업/기본값으로 폴백
def chat_json(system_prompt: str, user_prompt: str, temperature: float = 0.3) -> Optional[Dict[str, Any]]:
    if LLM_MODE == "openai" and OPENAI_API_KEY:
        try:
            raw = _openai_chat(
                [{"role":"system","content":system_prompt},
                 {"role":"user","content":user_prompt}],
                json_only=True, temperature=temperature
            )
            return json.loads(raw)
        except Exception:
            # [설명] 최후 폴백: 일반 텍스트 응답에서 첫 '{'와 마지막 '}' 사이를 파싱 시도
            raw = _openai_chat(
                [{"role":"system","content":system_prompt + "\nReturn JSON only."},
                 {"role":"user","content":user_prompt}],
                json_only=False, temperature=temperature
            )
            try:
                start = raw.find("{")
                end = raw.rfind("}")
                if start != -1 and end != -1:
                    return json.loads(raw[start:end+1])
            except Exception:
                return None
    # [설명] mock 모드: None을 반환하여 상위 로직이 목업/기본값 경로로 진행
    return None

# [설명] LLM 사용 가능 여부 플래그 (환경변수 기반)
def is_llm_available() -> bool:
    return LLM_MODE == "openai" and bool(OPENAI_API_KEY)
