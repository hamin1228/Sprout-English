"""
Sprout English — FastAPI 서버 실행 가이드
==========================================

이 파일은 프로젝트 루트의 server/main.py 입니다.
실제 FastAPI 애플리케이션 엔트리포인트는 server/app/main.py 입니다.

▶ 로컬 실행
-----------
cd server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

▶ Docker 실행
-------------
docker compose up --build
→ FastAPI: http://localhost:8000
→ API 문서: http://localhost:8000/docs

▶ 주요 환경변수
---------------
OPENAI_API_KEY      OpenAI API 키 (필수)
DB_HOST             MySQL 호스트 (Docker: mysql, 로컬: 127.0.0.1)
DB_PASSWORD         MySQL 비밀번호
REDIS_URL           Redis 연결 URL (기본: redis://localhost:6379/0)
CORS_ORIGINS        허용할 Origin 목록 (쉼표 구분, 기본: *)
"""
