"""The ML service rejects requests without the shared key once one is set.

Runs without a database: the key check happens before any handler runs.
    cd ml && pytest
"""
import importlib
import os

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("DATABASE_URL", "postgresql://unused@localhost/unused")


def client(key: str, monkeypatch) -> TestClient:
    monkeypatch.setenv("ML_API_KEY", key)
    import main
    importlib.reload(main)
    return TestClient(main.app)


def test_wrong_or_missing_key_is_rejected(monkeypatch):
    c = client("s3cret", monkeypatch)
    assert c.post("/recompute-all").status_code == 401
    assert c.post("/recompute-all", headers={"X-API-Key": "nope"}).status_code == 401


def test_right_key_reaches_the_handler(monkeypatch):
    c = client("s3cret", monkeypatch)
    import main
    monkeypatch.setattr(main, "_recompute", lambda sid: None)
    r = c.post("/recompute-all", headers={"X-API-Key": "s3cret"})
    assert r.status_code == 200
    assert r.json()["status"] == "started"


def test_no_key_configured_leaves_service_open(monkeypatch):
    c = client("", monkeypatch)
    import main
    monkeypatch.setattr(main, "_recompute", lambda sid: None)
    assert c.post("/recompute-all").status_code == 200


def test_recompute_only_rebuilds_students_without_mastery(monkeypatch):
    """Trigger-maintained mastery must not be overwritten by the BKT replay."""
    import pandas as pd
    c = client("", monkeypatch)
    import main
    monkeypatch.setattr(main, "fetch", lambda sql, *a: [{"student_id": "real"}])
    df = pd.DataFrame({"student_id": ["real", "synthetic", "synthetic"]})
    assert list(main._without_mastery(df)["student_id"]) == ["synthetic", "synthetic"]
