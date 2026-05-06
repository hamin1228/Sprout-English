FROM python:3.10-slim

WORKDIR /app

# 시스템 의존성 (soundfile, scipy 등 오디오 처리에 필요)
RUN apt-get update && apt-get install -y \
    gcc \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# 의존성 먼저 복사해서 캐시 활용
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 앱 소스 복사
COPY . .

# 오디오 저장 폴더 생성
RUN mkdir -p app/storage/audio

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
