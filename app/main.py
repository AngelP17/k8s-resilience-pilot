"""
The Resilience Pilot - FastAPI Application

A lightweight, production-ready API designed for SRE demonstrations:
- Health checks for Kubernetes liveness/readiness probes
- Prometheus metrics for observability
- Chaos injection endpoint for testing self-healing

SRE Concepts Demonstrated:
- Structured health endpoints (uptime tracking)
- Prometheus instrumentation (RED metrics)
- Graceful error handling
- Chaos engineering hooks
"""

import time
import random
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import JSONResponse
from prometheus_client import (
    Counter, 
    Histogram, 
    Gauge,
    generate_latest, 
    CONTENT_TYPE_LATEST,
    REGISTRY
)

# ============================================================================
# PROMETHEUS METRICS
# Following the RED method: Rate, Errors, Duration
# ============================================================================

# Rate: Request counter
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

# Duration: Request latency histogram
REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency in seconds',
    ['method', 'endpoint'],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)

# Errors: Error counter (subset of REQUEST_COUNT with status >= 400)
# Tracked via REQUEST_COUNT labels

# Additional useful gauges
UPTIME_GAUGE = Gauge(
    'app_uptime_seconds',
    'Application uptime in seconds'
)

# ============================================================================
# APPLICATION LIFECYCLE
# ============================================================================

# Track application start time for uptime calculation
START_TIME = time.time()

# Chaos state (simulates degraded service)
CHAOS_MODE = {"enabled": False, "probability": 0.0}


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup/shutdown events."""
    print("🚀 Resilience Pilot starting up...")
    yield
    print("👋 Resilience Pilot shutting down...")


app = FastAPI(
    title="The Resilience Pilot",
    description="A production-grade API for SRE demonstrations",
    version="1.0.0",
    lifespan=lifespan
)


# ============================================================================
# MIDDLEWARE: Request instrumentation
# ============================================================================

@app.middleware("http")
async def instrument_requests(request, call_next):
    """Middleware to instrument all requests with Prometheus metrics."""
    method = request.method
    endpoint = request.url.path
    
    start = time.time()
    
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception as e:
        status = 500
        raise e
    finally:
        duration = time.time() - start
        REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=status).inc()
        REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(duration)
    
    return response


# ============================================================================
# ENDPOINTS
# ============================================================================

@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "application": "The Resilience Pilot",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "metrics": "/metrics",
            "chaos": "/simulate-crash"
        }
    }


@app.get("/health")
async def health_check():
    """
    Health check endpoint for Kubernetes probes.
    
    Used by:
    - Liveness probe: Restart pod if this fails
    - Readiness probe: Remove from service if this fails
    
    Returns uptime in seconds for monitoring dashboards.
    """
    # Update uptime gauge
    uptime = time.time() - START_TIME
    UPTIME_GAUGE.set(uptime)
    
    # Check if chaos mode should trigger failure
    if CHAOS_MODE["enabled"] and random.random() < CHAOS_MODE["probability"]:
        REQUEST_COUNT.labels(method="GET", endpoint="/health", status=503).inc()
        raise HTTPException(
            status_code=503, 
            detail="Service degraded (chaos mode active)"
        )
    
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "uptime": round(uptime, 2),
            "uptime_formatted": format_uptime(uptime),
            "chaos_mode": CHAOS_MODE["enabled"]
        }
    )


@app.get("/metrics")
async def metrics():
    """
    Prometheus metrics endpoint.
    
    Exposes metrics in Prometheus text format for scraping.
    This endpoint is scraped by Prometheus every 15s by default.
    
    Key metrics:
    - http_requests_total: Request count by method, endpoint, status
    - http_request_duration_seconds: Latency histogram
    - app_uptime_seconds: Application uptime
    """
    # Update uptime before generating metrics
    UPTIME_GAUGE.set(time.time() - START_TIME)
    
    return Response(
        content=generate_latest(REGISTRY),
        media_type=CONTENT_TYPE_LATEST
    )


@app.post("/simulate-crash")
async def simulate_crash(
    mode: str = "immediate",
    probability: float = 1.0
):
    """
    Chaos engineering endpoint for testing self-healing.
    
    Modes:
    - "immediate": Instantly returns 500 error
    - "degraded": Enables probabilistic failures on /health
    - "reset": Disables chaos mode
    
    Args:
        mode: Type of chaos to inject
        probability: Failure probability for degraded mode (0.0-1.0)
    
    Example usage:
        curl -X POST "http://localhost:8080/simulate-crash?mode=immediate"
        curl -X POST "http://localhost:8080/simulate-crash?mode=degraded&probability=0.5"
        curl -X POST "http://localhost:8080/simulate-crash?mode=reset"
    """
    if mode == "immediate":
        # Immediate crash - triggers liveness probe failure
        REQUEST_COUNT.labels(method="POST", endpoint="/simulate-crash", status=500).inc()
        raise HTTPException(
            status_code=500,
            detail="💥 Chaos injected! This is an intentional crash for testing."
        )
    
    elif mode == "degraded":
        # Enable probabilistic failures
        CHAOS_MODE["enabled"] = True
        CHAOS_MODE["probability"] = min(max(probability, 0.0), 1.0)
        return {
            "status": "chaos_enabled",
            "mode": "degraded",
            "failure_probability": CHAOS_MODE["probability"],
            "message": f"Health endpoint will fail {CHAOS_MODE['probability']*100}% of the time"
        }
    
    elif mode == "reset":
        # Reset to healthy state
        CHAOS_MODE["enabled"] = False
        CHAOS_MODE["probability"] = 0.0
        return {
            "status": "chaos_disabled",
            "message": "Service restored to healthy state"
        }
    
    else:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown mode: {mode}. Use 'immediate', 'degraded', or 'reset'"
        )


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def format_uptime(seconds: float) -> str:
    """Format uptime in human-readable format."""
    days = int(seconds // 86400)
    hours = int((seconds % 86400) // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    
    if days > 0:
        return f"{days}d {hours}h {minutes}m {secs}s"
    elif hours > 0:
        return f"{hours}h {minutes}m {secs}s"
    elif minutes > 0:
        return f"{minutes}m {secs}s"
    else:
        return f"{secs}s"


# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=False,
        access_log=True
    )
