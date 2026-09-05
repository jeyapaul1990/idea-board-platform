"""API tests for Idea Board backend.

Uses an in-memory SQLite DB via FastAPI dependency overrides so CI does not
need a live Postgres instance. /readyz DB checks are patched where needed.
"""

from __future__ import annotations

from collections.abc import Generator
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    def override_get_db() -> Generator[Session, None, None]:
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_healthz_ok(client: TestClient) -> None:
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_readyz_ok_when_db_reachable(client: TestClient) -> None:
    with patch("app.main.check_database", return_value=True):
        res = client.get("/readyz")
    assert res.status_code == 200
    assert res.json()["status"] == "ready"


def test_readyz_fails_when_forced(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FORCE_READINESS_FAIL", "1")
    res = client.get("/readyz")
    assert res.status_code == 503
    assert res.json()["reason"] == "FORCE_READINESS_FAIL"


def test_create_and_list_ideas(client: TestClient) -> None:
    create = client.post("/api/ideas", json={"content": "ship tests"})
    assert create.status_code == 201
    body = create.json()
    assert body["content"] == "ship tests"
    assert "id" in body
    assert "created_at" in body

    listed = client.get("/api/ideas")
    assert listed.status_code == 200
    ideas = listed.json()
    assert len(ideas) >= 1
    assert ideas[0]["content"] == "ship tests"


def test_reject_empty_content(client: TestClient) -> None:
    # Pydantic min_length=1 → 422 for empty string
    empty = client.post("/api/ideas", json={"content": ""})
    assert empty.status_code == 422

    # Route strips whitespace → 400
    blank = client.post("/api/ideas", json={"content": "   "})
    assert blank.status_code == 400


def test_metrics_exposes_prometheus_text(client: TestClient) -> None:
    res = client.get("/metrics")
    assert res.status_code == 200
    assert "text/plain" in res.headers.get("content-type", "")
    assert "http_requests_total" in res.text or "# HELP" in res.text
