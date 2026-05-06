"""
/healthz 엔드포인트 통합 테스트.
실제 DB/Redis 없이 동작하며, DB 초기화는 background task로 실행되어
연결 실패 시에도 앱 자체는 기동된다.
"""
import pytest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient


@pytest.fixture(scope="module")
def client():
    with patch("app.db.init_db", new_callable=AsyncMock):
        from app.main import app
        with TestClient(app, raise_server_exceptions=True) as c:
            yield c


def test_healthz_returns_ok(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert "time" in body


def test_healthz_time_is_utc_iso(client):
    from datetime import datetime, timezone
    resp = client.get("/healthz")
    time_str = resp.json()["time"]
    # 'Z' suffix 또는 '+00:00' suffix 허용
    time_str_normalized = time_str.replace("Z", "+00:00")
    dt = datetime.fromisoformat(time_str_normalized)
    assert dt.year >= 2024


def test_root_returns_200(client):
    resp = client.get("/")
    assert resp.status_code == 200
