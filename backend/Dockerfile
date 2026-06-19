# Backend runs CPU-only (it orchestrates vLLM/whisper over HTTP), so a slim
# base on arm64 is fine for the DGX Spark.
#
# Build context is the repository root (see docker-compose.yml) so the web
# frontend can be copied in alongside the backend.
FROM python:3.11-slim

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/app ./app

# The web frontend is mounted at "/" if present; copy it in so a single
# container yields a usable URL on the LAN.
COPY frontend ./frontend

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
