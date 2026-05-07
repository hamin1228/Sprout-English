from __future__ import annotations

from fastapi import APIRouter

from app.schemas import GenerateRequest, GenerateResponse, GradeRequest, GradeResponse
from app.toeic import generate_toeic_set, grade_toeic_set

router = APIRouter()


@router.post("/toeic/generate", response_model=GenerateResponse)
async def toeic_generate(req: GenerateRequest):
    return generate_toeic_set(req)


@router.post("/toeic/grade", response_model=GradeResponse)
async def toeic_grade(req: GradeRequest):
    return grade_toeic_set(req)
