"""
config_loader.py 단위 테스트.
pydantic_settings Settings가 환경변수를 올바르게 읽는지,
CORS 헬퍼 함수가 '*' 와 다중 Origin을 올바르게 처리하는지 검증한다.
"""
import os
import pytest


def test_settings_loads_from_env():
    from app.config_loader import settings
    assert settings.DB_USER == os.environ["DB_USER"]
    assert settings.OPENAI_API_KEY == os.environ["OPENAI_API_KEY"]
    assert settings.APP_ENV == "test"


def test_get_cors_origins_wildcard():
    from app.config_loader import get_cors_origins
    os.environ["CORS_ORIGINS"] = "*"
    result = get_cors_origins()
    assert result == ["*"]


def test_get_cors_origins_multi():
    import importlib
    import app.config_loader as cfg_mod

    original = cfg_mod.settings.CORS_ORIGINS
    cfg_mod.settings.CORS_ORIGINS = "https://a.com, https://b.com"
    try:
        result = cfg_mod.get_cors_origins()
        assert "https://a.com" in result
        assert "https://b.com" in result
        assert len(result) == 2
    finally:
        cfg_mod.settings.CORS_ORIGINS = original


def test_get_cors_allow_credentials_wildcard():
    import app.config_loader as cfg_mod
    original = cfg_mod.settings.CORS_ORIGINS
    cfg_mod.settings.CORS_ORIGINS = "*"
    try:
        assert cfg_mod.get_cors_allow_credentials() is False
    finally:
        cfg_mod.settings.CORS_ORIGINS = original


def test_get_cors_allow_credentials_explicit():
    import app.config_loader as cfg_mod
    original = cfg_mod.settings.CORS_ORIGINS
    cfg_mod.settings.CORS_ORIGINS = "https://app.example.com"
    try:
        assert cfg_mod.get_cors_allow_credentials() is True
    finally:
        cfg_mod.settings.CORS_ORIGINS = original
