from __future__ import annotations

from fastapi import APIRouter, Body

from app.schemas import RoleplayCatalogResponse, RoleplayGenerateRequest, RoleplayGenerateResponse
from app.services.roleplay import generate as roleplay_generate, get_catalog as roleplay_get_catalog

router = APIRouter()


@router.get("/roleplay/catalog", response_model=RoleplayCatalogResponse)
async def roleplay_catalog_api():
    return roleplay_get_catalog()


@router.post("/roleplay/generate", response_model=RoleplayGenerateResponse)
async def roleplay_generate_api(payload: RoleplayGenerateRequest = Body(...)):
    return await roleplay_generate(payload)
