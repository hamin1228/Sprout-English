# server/app/state_machine.py
from __future__ import annotations
from typing import Optional
from app.schemas import RoleplaySessionState

def _goal_reached(state: RoleplaySessionState) -> bool:
    # 심플 휴리스틱: 목표문구가 variables["achieved"] or 남은 턴 <= 2 일 때
    remaining = max(0, state.target_turns - state.turn_index)
    return bool(state.variables.get("achieved")) or remaining <= 2

def next_state(prev: RoleplaySessionState, user_input: Optional[str]) -> RoleplaySessionState:
    s = prev.copy(deep=True)

    if s.state == "INIT":
        s.state = "INTRO"
        return s

    if s.state == "INTRO":
        # 첫 사용자 입력 도착하면 대화로
        if user_input and user_input.strip():
            s.state = "DIALOGUE"
        return s

    if s.state == "DIALOGUE":
        if _goal_reached(s) or s.turn_index >= s.target_turns:
            s.state = "REVIEW"
        return s

    if s.state == "REVIEW":
        s.state = "ENDED"
        return s

    # ENDED 유지
    return s