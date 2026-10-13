from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root_returns_welcome_message() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {
        "message": "Welcome to the CI/CD FastAPI application"
    }


def test_health_returns_healthy_status() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_version_returns_default_version() -> None:
    response = client.get("/version")

    assert response.status_code == 200
    assert response.json() == {"version": "1.0.0"}


def test_unknown_route_returns_not_found() -> None:
    response = client.get("/does-not-exist")

    assert response.status_code == 404
