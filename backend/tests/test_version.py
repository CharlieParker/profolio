from fastapi.testclient import TestClient

from app.database import Settings, settings
from app.main import app

client = TestClient(app)

# A dummy value throughout: these check the plumbing from env var to response, not
# that any real commit exists.
DUMMY_SHA = "0123456789abcdef0123456789abcdef01234567"


def test_git_sha_setting_is_read_from_the_env_var_the_dockerfile_sets(monkeypatch):
    monkeypatch.setenv("GIT_SHA", DUMMY_SHA)
    assert Settings().git_sha == DUMMY_SHA


def test_version_reports_the_build_commit_with_a_link(monkeypatch):
    monkeypatch.setattr(settings, "git_sha", DUMMY_SHA)
    response = client.get("/api/version")
    assert response.status_code == 200
    assert response.json() == {
        "service": "profolio-backend",
        "commit": DUMMY_SHA,
        "commit_url": f"https://github.com/CharlieParker/profolio/commit/{DUMMY_SHA}",
    }


def test_version_without_a_build_commit_has_no_link(monkeypatch):
    monkeypatch.setattr(settings, "git_sha", "unknown")
    response = client.get("/api/version")
    assert response.status_code == 200
    assert response.json() == {
        "service": "profolio-backend",
        "commit": "unknown",
        "commit_url": None,
    }
