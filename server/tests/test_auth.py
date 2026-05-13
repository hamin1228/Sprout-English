"""
Auth API 테스트.
실제 MySQL DB 없이 SQLite in-memory DB를 사용한다.
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db import get_session
from app.main import app
from app.models import Base

# SQLite in-memory DB (테스트용)
_TEST_DB_URL = "sqlite+aiosqlite:///:memory:"


@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture(scope="session")
async def db_engine():
    engine = create_async_engine(_TEST_DB_URL, echo=False, future=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture()
async def db_session(db_engine):
    factory = async_sessionmaker(bind=db_engine, expire_on_commit=False, class_=AsyncSession)
    async with factory() as session:
        yield session
        await session.rollback()


@pytest.fixture()
async def client(db_session):
    async def _override_get_session():
        yield db_session

    app.dependency_overrides[get_session] = _override_get_session
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


# ── 테스트 ────────────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_signup_success(client: AsyncClient):
    resp = await client.post("/auth/signup", json={
        "email": "test@example.com",
        "password": "password123",
        "nickname": "테스터",
    })
    assert resp.status_code == 201
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["user"]["email"] == "test@example.com"


@pytest.mark.anyio
async def test_signup_duplicate_email(client: AsyncClient):
    payload = {"email": "dup@example.com", "password": "password123"}
    await client.post("/auth/signup", json=payload)
    resp = await client.post("/auth/signup", json=payload)
    assert resp.status_code == 409


@pytest.mark.anyio
async def test_login_success(client: AsyncClient):
    await client.post("/auth/signup", json={
        "email": "login@example.com",
        "password": "password123",
    })
    resp = await client.post("/auth/login", json={
        "email": "login@example.com",
        "password": "password123",
    })
    assert resp.status_code == 200
    assert "access_token" in resp.json()


@pytest.mark.anyio
async def test_login_wrong_password(client: AsyncClient):
    await client.post("/auth/signup", json={
        "email": "wrongpw@example.com",
        "password": "password123",
    })
    resp = await client.post("/auth/login", json={
        "email": "wrongpw@example.com",
        "password": "wrongpassword",
    })
    assert resp.status_code == 401


@pytest.mark.anyio
async def test_me_without_token(client: AsyncClient):
    resp = await client.get("/auth/me")
    assert resp.status_code == 403  # HTTPBearer는 토큰 없으면 403 반환


@pytest.mark.anyio
async def test_me_with_token(client: AsyncClient):
    signup = await client.post("/auth/signup", json={
        "email": "me@example.com",
        "password": "password123",
    })
    token = signup.json()["access_token"]
    resp = await client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert resp.json()["email"] == "me@example.com"


@pytest.mark.anyio
async def test_refresh_token(client: AsyncClient):
    signup = await client.post("/auth/signup", json={
        "email": "refresh@example.com",
        "password": "password123",
    })
    refresh_token = signup.json()["refresh_token"]
    resp = await client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    assert "access_token" in resp.json()
