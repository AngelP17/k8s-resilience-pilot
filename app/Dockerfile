################################################################################
# The Resilience Pilot - Multi-Stage Dockerfile
#
# Security Best Practices Demonstrated:
# - Multi-stage build (minimal attack surface)
# - Non-root user (principle of least privilege)
# - Pinned base image version (reproducibility)
# - No unnecessary packages installed
# - Health check instruction for container orchestrators
################################################################################

# =============================================================================
# STAGE 1: Builder
# Install dependencies in a separate stage to reduce final image size
# =============================================================================
FROM python:3.11-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt


# =============================================================================
# STAGE 2: Runtime
# Minimal image with only runtime requirements
# =============================================================================
FROM python:3.11-slim as runtime

# Security: Run as non-root user
# This follows the principle of least privilege
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /root/.local /home/appuser/.local

# Ensure scripts in .local are usable
ENV PATH=/home/appuser/.local/bin:$PATH

# Copy application code
COPY --chown=appuser:appgroup main.py .

# Switch to non-root user
USER appuser

# Expose the application port
EXPOSE 8080

# Health check for container orchestrators
# This is in addition to Kubernetes probes and helps Docker Compose/Swarm
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Labels for container metadata (OCI standard)
LABEL org.opencontainers.image.title="The Resilience Pilot"
LABEL org.opencontainers.image.description="Production-grade SRE demonstration API"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.authors="SRE Team"

# Run the application
# Using exec form to ensure proper signal handling (important for graceful shutdown)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
