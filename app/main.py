import os

from fastapi import FastAPI

app = FastAPI(title="CI/CD FastAPI Application")


@app.get("/")
def read_root() -> dict[str, str]:
    return {"message": "Welcome to the CI/CD FastAPI application"}


@app.get("/health")
def read_health() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/version")
def read_version() -> dict[str, str]:
    return {"version": os.getenv("APP_VERSION", "1.0.0")}
