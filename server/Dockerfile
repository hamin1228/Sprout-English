FROM --platform=linux/amd64 python:3.10-slim AS base

WORKDIR /app

# 시스템 의존성 (오디오 처리: soundfile, scipy, ffmpeg)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libsndfile1 \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# --- 의존성 레이어 (소스 변경 시 캐시 재사용) ---
FROM base AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- 최종 이미지 ---
FROM base AS final
COPY --from=deps /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

COPY . .

RUN mkdir -p app/storage/audio

# 루트 권한 제거 (보안)
RUN useradd -m appuser && chown -R appuser /app
USER appuser

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
