import os
import time

from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from app.config import settings
from app.db import check_database
from app.routes import router

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
)

app = FastAPI(title="Idea Board API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)


@app.middleware("http")
async def metrics_middleware(request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)
    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start
    endpoint = request.url.path
    REQUEST_COUNT.labels(request.method, endpoint, response.status_code).inc()
    REQUEST_LATENCY.labels(request.method, endpoint).observe(elapsed)
    return response


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness: process is up. Must not depend on downstream services."""
    return {"status": "ok"}


@app.get("/readyz", response_model=None)
def readyz():
    """Readiness: can serve traffic (database reachable)."""
    if settings.force_readiness_fail or os.getenv("FORCE_READINESS_FAIL") == "1":
        return Response(
            content='{"status":"not_ready","reason":"FORCE_READINESS_FAIL"}',
            status_code=503,
            media_type="application/json",
        )
    try:
        check_database()
    except Exception as exc:
        return Response(
            content=f'{{"status":"not_ready","reason":"{type(exc).__name__}"}}',
            status_code=503,
            media_type="application/json",
        )
    return {"status": "ready"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
