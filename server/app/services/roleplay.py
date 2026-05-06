from __future__ import annotations

import asyncio
import json
import os
import re
import time
import uuid
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import HTTPException

from app.schemas import (
    Chunk,
    Pace,
    RoleplayCatalogItem,
    RoleplayCatalogResponse,
    RoleplayGenerateRequest,
    RoleplayGenerateResponse,
    RoleplayMessage,
    RoleplaySessionState,
    RoleplayStageSummary,
)
from app.services import llm as llm_service


CATALOG_PATH = Path(__file__).resolve().parents[3] / "assets" / "roleplay" / "catalog.json"
_WORD_RE = re.compile(r"[A-Za-z']+")
_HANGUL_RE = re.compile(r"[가-힣]")
_OFF_REPLIES = {"ok", "okay", "k", "yes", "yeah", "yep", "sure", "hmm", "uh", "um"}
_OPTIONAL_SKIP_STAGE_IDS = {"extra_option", "room_request"}
_SKIP_INTENT_PHRASES = (
    "no thanks",
    "no thank you",
    "no extra",
    "no extras",
    "no option",
    "no options",
    "nothing else",
    "none",
    "that's all",
    "thats all",
    "that's it",
    "thats it",
    "i'm good",
    "im good",
    "skip that",
    "skip it",
    "without extra",
    "without extras",
    "without sugar",
    "without milk",
    "no preference",
    "any is fine",
)


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() not in {"0", "false", "no", "off"}


class _Session:
    def __init__(self, sid: str, state: RoleplaySessionState, history: List[RoleplayMessage]):
        self.sid = sid
        self.state = state
        self.history = history
        self.lock = asyncio.Lock()
        self.ts = time.time()


class SessionStore:
    def __init__(self, ttl_seconds: int = 7200):
        self._db: Dict[str, _Session] = {}
        self._ttl = ttl_seconds

    def _now(self) -> float:
        return time.time()

    def _prune(self) -> None:
        now = self._now()
        stale = [
            sid
            for sid, sess in self._db.items()
            if (now - sess.ts) > self._ttl or sess.state.state == "ENDED"
        ]
        for sid in stale:
            self._db.pop(sid, None)

    def get(self, sid: str) -> Optional[_Session]:
        self._prune()
        sess = self._db.get(sid)
        if sess:
            sess.ts = self._now()
        return sess

    def create(self, state: RoleplaySessionState, history: Optional[List[RoleplayMessage]] = None) -> _Session:
        self._prune()
        sid = uuid.uuid4().hex
        sess = _Session(sid, state, history or [])
        self._db[sid] = sess
        return sess

    def clear(self) -> None:
        self._db.clear()


STORE = SessionStore()


@lru_cache(maxsize=1)
def _load_catalog_raw() -> List[Dict[str, Any]]:
    if not CATALOG_PATH.exists():
        raise FileNotFoundError(f"Roleplay catalog not found: {CATALOG_PATH}")
    data = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("Roleplay catalog must be a list.")
    return data


@lru_cache(maxsize=1)
def _catalog_map() -> Dict[str, Dict[str, Any]]:
    return {item["id"]: item for item in _load_catalog_raw()}


def _stage_summary(stage: Dict[str, Any]) -> RoleplayStageSummary:
    return RoleplayStageSummary(
        id=str(stage["id"]),
        title=str(stage["title"]),
        objective_ko=str(stage["objective_ko"]),
        hint_en=str(stage["hint_en"]),
    )


def get_catalog() -> RoleplayCatalogResponse:
    items = [
        RoleplayCatalogItem(
            id=str(item["id"]),
            difficulty=str(item["difficulty"]),
            title=str(item["title"]),
            subtitle=str(item["subtitle"]),
            summary_ko=str(item["summary_ko"]),
            estimated_minutes=int(item["estimated_minutes"]),
            background_asset=str(item["background_asset"]),
            ai_role=str(item["ai_role"]),
            user_goal_ko=str(item["user_goal_ko"]),
            opening_line=str(item["opening_line"]),
            stages=[_stage_summary(stage) for stage in item["stages"]],
        )
        for item in _load_catalog_raw()
    ]
    return RoleplayCatalogResponse(items=items)


def _get_scenario(scenario_id: str) -> Dict[str, Any]:
    scenario = _catalog_map().get(scenario_id)
    if not scenario:
        raise HTTPException(status_code=404, detail=f"Unknown scenario_id: {scenario_id}")
    return scenario


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower()).strip()


def _count_words(text: str) -> int:
    return len(_WORD_RE.findall(text))


def _is_question(text: str) -> bool:
    norm = _normalize(text)
    if "?" in text:
        return True
    return any(
        norm.startswith(prefix)
        for prefix in (
            "what",
            "where",
            "when",
            "why",
            "who",
            "how",
            "can",
            "could",
            "would",
            "do",
            "does",
            "did",
            "is",
            "are",
            "will",
        )
    )


def _match_phrase(norm_text: str, phrase: str) -> bool:
    norm_phrase = _normalize(phrase)
    if not norm_phrase:
        return False
    return norm_phrase in norm_text


def _is_optional_skip_stage(stage: Dict[str, Any]) -> bool:
    stage_id = str(stage.get("id", "")).strip().lower()
    if stage_id in _OPTIONAL_SKIP_STAGE_IDS:
        return True
    return bool(stage.get("allow_skip_intent"))


def _detect_skip_intent(text: str) -> bool:
    norm = _normalize(text)
    if not norm:
        return False
    return any(_match_phrase(norm, phrase) for phrase in _SKIP_INTENT_PHRASES)


def _stage_attempts(state: RoleplaySessionState) -> Dict[str, int]:
    raw = state.variables.get("stage_attempts")
    if not isinstance(raw, dict):
        raw = {}
    cleaned: Dict[str, int] = {}
    for key, value in raw.items():
        try:
            cleaned[str(key)] = max(0, int(value))
        except Exception:
            cleaned[str(key)] = 0
    state.variables["stage_attempts"] = cleaned
    return cleaned


def _get_stage_attempt(state: RoleplaySessionState, stage_id: str) -> int:
    return _stage_attempts(state).get(stage_id, 0)


def _increment_stage_attempt(state: RoleplaySessionState, stage_id: str) -> int:
    data = _stage_attempts(state)
    data[stage_id] = data.get(stage_id, 0) + 1
    return data[stage_id]


def _reset_stage_attempt(state: RoleplaySessionState, stage_id: str) -> None:
    data = _stage_attempts(state)
    data.pop(stage_id, None)


def _missing_group_hint(evaluation: Dict[str, Any]) -> Optional[str]:
    missing = evaluation.get("missing_examples")
    if not isinstance(missing, list) or not missing:
        return None
    candidates = [str(item).strip() for item in missing if str(item).strip()]
    if not candidates:
        return None
    if len(candidates) == 1:
        return f"Could you add something about '{candidates[0]}'?"
    return f"Could you add something about '{candidates[0]}' or '{candidates[1]}'?"


def _skip_transition_prefix(stage: Dict[str, Any]) -> str:
    stage_id = str(stage.get("id", "")).strip().lower()
    if stage_id == "extra_option":
        return "No problem, we can skip extra options."
    if stage_id == "room_request":
        return "No problem, we can continue without special room requests."
    return "No problem, we can skip that and move on."


def _roleplay_llm_enabled() -> bool:
    if not _env_bool("ROLEPLAY_LLM_ENABLED", True):
        return False
    return bool(llm_service.OPENAI_API_KEY)


def _scenario_keyword_hit(scenario: Dict[str, Any], text: str) -> bool:
    norm = _normalize(text)
    keywords = list(scenario.get("topic_keywords") or [])
    for stage in scenario["stages"]:
        for group in stage.get("required_groups", []):
            keywords.extend(group)
        if stage.get("closing_keywords"):
            keywords.extend(stage["closing_keywords"])
    return any(_match_phrase(norm, keyword) for keyword in keywords)


def _current_stage(state: RoleplaySessionState, scenario: Dict[str, Any]) -> Dict[str, Any]:
    stages = scenario["stages"]
    index = max(0, min(state.stage_index, len(stages) - 1))
    return stages[index]


def _build_chunks(text: str, pace: Pace) -> List[Chunk]:
    limit = {"slow": 80, "normal": 160, "fast": 280}[pace]
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    chunks: List[str] = []
    buf = ""
    for part in parts:
        if len(buf) + len(part) + 1 <= limit:
            buf = (buf + " " + part).strip()
        else:
            if buf:
                chunks.append(buf)
            buf = part
    if buf:
        chunks.append(buf)
    if not chunks:
        chunks = [text.strip() or "..."]
    final: List[Chunk] = []
    for index, chunk in enumerate(chunks):
        final.append(Chunk(index=index, text=chunk, is_last=index == len(chunks) - 1))
    return final


def _safe_sentence(text: str) -> str:
    compact = re.sub(r"\s+", " ", text).strip()
    return compact if compact.endswith((".", "!", "?")) else f"{compact}."


def _polish_with_llm(
    *,
    scenario: Dict[str, Any],
    stage: Dict[str, Any],
    draft: str,
    user_input: Optional[str],
    should_redirect: bool,
    recent_history: Optional[List[RoleplayMessage]] = None,
    stage_attempt: int = 0,
) -> str:
    if not _roleplay_llm_enabled():
        return draft
    try:
        history_lines: List[str] = []
        if recent_history:
            for item in recent_history[-4:]:
                role = str(getattr(item, "role", "")).strip()
                content = str(getattr(item, "content", "")).strip()
                if not role or not content:
                    continue
                history_lines.append(f"{role}: {content}")
        recent_dialogue = "\n".join(history_lines) if history_lines else "(none)"
        system = (
            "You are an English roleplay partner in a language-learning app. "
            "Prioritize natural conversation and user intent over rigid templates. "
            "Stay broadly inside the scenario, but do not force scripted wording. "
            "Accept short answers (even 1-2 words) when intent is clear. "
            "Avoid repetitive coaching like 'you can say'. "
            "If the user declines an option, acknowledge and move on. "
            "Keep replies concise, conversational, and context-aware (1-3 sentences). "
            "Do not use markdown or bullet points."
        )
        user = (
            f"Scenario: {scenario['title']}\n"
            f"AI role: {scenario['ai_role']}\n"
            f"Stage: {stage['title']}\n"
            f"Objective: {stage['objective_ko']}\n"
            f"Hint: {stage['hint_en']}\n"
            f"Stage attempts so far: {stage_attempt}\n"
            f"Recent dialogue:\n{recent_dialogue}\n"
            f"User input: {user_input or '(none)'}\n"
            f"Redirect: {should_redirect}\n"
            f"Draft response: {draft}\n"
            "Rewrite or replace the draft so the reply sounds natural and helpful."
        )
        raw = llm_service._openai_chat(  # type: ignore[attr-defined]
            [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            json_only=False,
            temperature=0.4,
        )
        polished = _safe_sentence(raw)
        return polished if polished else draft
    except Exception:
        return draft


def _append_history(history: List[RoleplayMessage], role: str, content: str) -> None:
    history.append(RoleplayMessage(role=role, content=content))


def _evaluate_stage(stage: Dict[str, Any], scenario: Dict[str, Any], text: str) -> Dict[str, Any]:
    norm = _normalize(text)
    word_count = _count_words(text)
    required_groups: List[List[str]] = []
    for group in stage.get("required_groups", []):
        if not isinstance(group, list):
            continue
        phrases = [str(item).strip() for item in group if str(item).strip()]
        if phrases:
            required_groups.append(phrases)

    matched_groups = 0
    missing_examples: List[str] = []
    for group in required_groups:
        if any(_match_phrase(norm, phrase) for phrase in group):
            matched_groups += 1
        else:
            missing_examples.append(group[0])

    total_groups = len(required_groups)
    requires_question = bool(stage.get("requires_question"))
    min_words = int(stage.get("min_words", 2))
    has_closing = bool(stage.get("closing_keywords"))
    closing_ok = True
    if has_closing:
        closing_ok = any(_match_phrase(norm, phrase) for phrase in stage.get("closing_keywords", []))

    skip_allowed = _is_optional_skip_stage(stage)
    skip_intent = skip_allowed and _detect_skip_intent(text)

    group_ok = total_groups == 0 or matched_groups == total_groups or skip_intent
    question_ok = not requires_question or _is_question(text)
    word_ok = word_count >= min_words
    completed = group_ok and question_ok and word_ok and closing_ok
    completed_via_skip = completed and skip_intent and matched_groups < total_groups
    scenario_hit = _scenario_keyword_hit(scenario, text)
    has_hangul = bool(_HANGUL_RE.search(text))

    if has_hangul:
        outcome = "hangul"
    elif completed:
        outcome = "completed"
    elif word_count < max(2, min_words) and matched_groups == 0 and not skip_intent:
        outcome = "short"
    elif matched_groups > 0 or scenario_hit:
        outcome = "partial"
    else:
        outcome = "redirect"

    return {
        "outcome": outcome,
        "completed": completed,
        "matched_groups": matched_groups,
        "scenario_hit": scenario_hit,
        "word_count": word_count,
        "requires_question": requires_question,
        "question_ok": question_ok,
        "word_ok": word_ok,
        "closing_ok": closing_ok,
        "missing_groups": max(0, total_groups - matched_groups),
        "missing_examples": missing_examples,
        "skip_allowed": skip_allowed,
        "skip_intent": skip_intent,
        "completed_via_skip": completed_via_skip,
    }


def _fallback_response(stage: Dict[str, Any], outcome: str, evaluation: Dict[str, Any], stage_attempt: int) -> str:
    starter = stage.get("starter") or stage.get("ai_prompt") or "Try one short sentence."
    if outcome == "hangul":
        return _safe_sentence(f"Let's try that in English. You can say: {starter}")
    if outcome == "short":
        if stage_attempt >= 1:
            return _safe_sentence(str(stage.get("ai_prompt") or starter))
        return _safe_sentence(f"Got it. {stage.get('ai_prompt') or starter}")

    hint = _missing_group_hint(evaluation)
    if stage_attempt >= 2 and hint:
        return _safe_sentence(f"Let's stay in this scene. {hint}")
    if stage_attempt >= 1:
        return _safe_sentence(f"Let's stay in this scene. {stage.get('redirect_question')}")
    return _safe_sentence(f"That's interesting. {stage['redirect_question']}")


def _transition_response(prev_stage: Dict[str, Any], next_stage: Optional[Dict[str, Any]], scenario: Dict[str, Any]) -> str:
    if next_stage is None:
        return _safe_sentence(
            f"{prev_stage['acknowledgement']} You completed the scenario well. Thanks for staying in character."
        )
    return _safe_sentence(f"{prev_stage['acknowledgement']} {next_stage['ai_prompt']}")


def _continuation_response(stage: Dict[str, Any], evaluation: Dict[str, Any], stage_attempt: int) -> str:
    if stage.get("requires_question") and not evaluation["question_ok"]:
        return _safe_sentence(f"Make it a question this time. {stage['starter']}")
    hint = _missing_group_hint(evaluation)
    if hint:
        if stage_attempt >= 2:
            return _safe_sentence(f"Got it. {hint}")
        return _safe_sentence(f"Nice. {hint}")
    if not evaluation["word_ok"]:
        return _safe_sentence(f"Add a little more detail. {stage['starter']}")
    return _safe_sentence(stage["ai_prompt"])


def _should_soft_advance(stage: Dict[str, Any], evaluation: Dict[str, Any], stage_attempt: int, user_input: str) -> bool:
    if evaluation.get("completed"):
        return True
    if evaluation.get("outcome") in {"redirect", "hangul"}:
        return False
    if stage.get("requires_question") and not evaluation.get("question_ok"):
        return False

    matched = int(evaluation.get("matched_groups", 0))
    total_groups = max(1, matched + int(evaluation.get("missing_groups", 0)))
    coverage = matched / float(total_groups)
    words = int(evaluation.get("word_count", 0))
    norm = _normalize(user_input)

    if matched <= 0:
        return False
    if coverage >= 0.7:
        return True
    if coverage >= 0.5 and words >= 1:
        return True
    if stage_attempt >= 1 and coverage >= 0.34:
        return True
    if norm in _OFF_REPLIES and stage_attempt >= 2:
        return True
    return False


def _make_state_from_scenario(req: RoleplayGenerateRequest, scenario: Dict[str, Any]) -> RoleplaySessionState:
    return RoleplaySessionState(
        state="INTRO",
        turn_index=0,
        scenario_id=str(scenario["id"]),
        difficulty=str(req.difficulty or scenario["difficulty"]),
        goal=req.goal or str(scenario["user_goal_ko"]),
        persona=req.persona or str(scenario["ai_role"]),
        target_turns=max(12, len(scenario["stages"]) * 2),
        stage_index=0,
        stage_status="awaiting_user",
        completed_objectives=[],
        redirect_count=0,
        is_complete=False,
        estimated_minutes=int(scenario["estimated_minutes"]),
        variables={"input_source": req.input_source},
    )


def _response_for_current_stage(
    *,
    session_id: str,
    state: RoleplaySessionState,
    scenario: Dict[str, Any],
    text: str,
    pace: Pace,
    should_redirect: bool,
) -> RoleplayGenerateResponse:
    stage = None if state.is_complete else _current_stage(state, scenario)
    return RoleplayGenerateResponse(
        session_id=session_id,
        turn_index=state.turn_index,
        assistant_utterance=text,
        current_stage_title=None if stage is None else str(stage["title"]),
        current_objective_ko=None if stage is None else str(stage["objective_ko"]),
        hint_en=None if stage is None else str(stage["hint_en"]),
        should_redirect=should_redirect,
        session_complete=state.is_complete,
        tts_text=text,
        chunks=_build_chunks(text, pace),
        state=state,
        meta={
            "scenario_id": scenario["id"],
            "scenario_title": scenario["title"],
            "difficulty": scenario["difficulty"],
            "estimated_minutes": scenario["estimated_minutes"],
            "completed_objectives": list(state.completed_objectives),
            "input_source": state.variables.get("input_source"),
        },
    )


async def generate(req: RoleplayGenerateRequest) -> RoleplayGenerateResponse:
    session = STORE.get(req.session_id) if req.session_id else None
    if session and req.scenario_id and req.scenario_id != session.state.scenario_id:
        raise HTTPException(status_code=409, detail="scenario_id does not match the existing session")

    if not session:
        if not req.scenario_id:
            raise HTTPException(status_code=422, detail="scenario_id is required for a new roleplay session")
        scenario = _get_scenario(req.scenario_id)
        state = _make_state_from_scenario(req, scenario)
        session = STORE.create(state, req.seed_history)
    else:
        scenario = _get_scenario(str(session.state.scenario_id))

    async with session.lock:
        state = session.state
        if req.input_source:
            state.variables["input_source"] = req.input_source

        if state.is_complete:
            final_text = "This scenario is already complete. You can start a new roleplay anytime."
            _append_history(session.history, "assistant", final_text)
            state.turn_index += 1
            return _response_for_current_stage(
                session_id=session.sid,
                state=state,
                scenario=scenario,
                text=final_text,
                pace=req.pace,
                should_redirect=False,
            )

        if not req.user_input:
            opening = _safe_sentence(scenario["opening_line"])
            state.state = "INTRO"
            state.stage_status = "awaiting_user"
            state.turn_index += 1
            _append_history(session.history, "assistant", opening)
            return _response_for_current_stage(
                session_id=session.sid,
                state=state,
                scenario=scenario,
                text=opening,
                pace=req.pace,
                should_redirect=False,
            )

        _append_history(session.history, "user", req.user_input)
        stage = _current_stage(state, scenario)
        stage_id = str(stage.get("id") or f"stage_{state.stage_index}")
        stage_attempt = _get_stage_attempt(state, stage_id)
        evaluation = _evaluate_stage(stage, scenario, req.user_input)
        if _should_soft_advance(stage, evaluation, stage_attempt, req.user_input):
            evaluation["completed"] = True
            if not evaluation.get("completed_via_skip"):
                evaluation["completed_via_soft"] = True
            evaluation["outcome"] = "completed"
        should_redirect = evaluation["outcome"] == "redirect"

        if evaluation["outcome"] in {"hangul", "short", "redirect"}:
            if should_redirect:
                state.redirect_count += 1
            state.stage_status = "awaiting_user"
            state.state = "DIALOGUE"
            draft = _fallback_response(stage, evaluation["outcome"], evaluation, stage_attempt)
            text = _polish_with_llm(
                scenario=scenario,
                stage=stage,
                draft=draft,
                user_input=req.user_input,
                should_redirect=should_redirect,
                recent_history=session.history,
                stage_attempt=stage_attempt,
            )
            _increment_stage_attempt(state, stage_id)
        elif evaluation["completed"]:
            _reset_stage_attempt(state, stage_id)
            if stage["id"] not in state.completed_objectives:
                state.completed_objectives.append(str(stage["id"]))
            last_stage = state.stage_index >= len(scenario["stages"]) - 1
            if last_stage:
                state.is_complete = True
                state.stage_status = "completed"
                state.state = "ENDED"
                draft = _transition_response(stage, None, scenario)
                if evaluation.get("completed_via_soft"):
                    draft = _safe_sentence(
                        f"Thanks, that works. You completed this roleplay. Nice work staying in character."
                    )
                text = _polish_with_llm(
                    scenario=scenario,
                    stage=stage,
                    draft=draft,
                    user_input=req.user_input,
                    should_redirect=False,
                    recent_history=session.history,
                    stage_attempt=stage_attempt,
                )
            else:
                state.stage_index += 1
                next_stage = _current_stage(state, scenario)
                state.stage_status = "awaiting_user"
                state.state = "DIALOGUE"
                draft = _transition_response(stage, next_stage, scenario)
                if evaluation.get("completed_via_skip"):
                    draft = _safe_sentence(f"{_skip_transition_prefix(stage)} {next_stage['ai_prompt']}")
                elif evaluation.get("completed_via_soft"):
                    draft = _safe_sentence(f"Got it, thanks. {next_stage['ai_prompt']}")
                text = _polish_with_llm(
                    scenario=scenario,
                    stage=next_stage,
                    draft=draft,
                    user_input=req.user_input,
                    should_redirect=False,
                    recent_history=session.history,
                    stage_attempt=0,
                )
        else:
            state.stage_status = "awaiting_user"
            state.state = "DIALOGUE"
            draft = _continuation_response(stage, evaluation, stage_attempt)
            text = _polish_with_llm(
                scenario=scenario,
                stage=stage,
                draft=draft,
                user_input=req.user_input,
                should_redirect=False,
                recent_history=session.history,
                stage_attempt=stage_attempt,
            )
            _increment_stage_attempt(state, stage_id)

        state.turn_index += 1
        _append_history(session.history, "assistant", text)
        session.state = state
        return _response_for_current_stage(
            session_id=session.sid,
            state=state,
            scenario=scenario,
            text=text,
            pace=req.pace,
            should_redirect=should_redirect,
        )


def reset_store_for_tests() -> None:
    STORE.clear()
