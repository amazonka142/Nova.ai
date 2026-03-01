# Nova.ai Backend (PostgreSQL + SQLAlchemy)

Минимальный backend для перехода с Firestore на реальную реляционную БД.

## Стек
- PostgreSQL
- SQLAlchemy 2.0
- Alembic
- FastAPI

## Быстрый старт (Docker)
Команды выполняются из корня репозитория (`/Users/macuser/Desktop/Nova.ai`).

1. Скопировать переменные:
   ```bash
   cp .env.example .env
   ```
2. Поднять сервисы:
   ```bash
   docker compose up --build
   ```
3. Проверка health:
   - [http://localhost:8000/health](http://localhost:8000/health)

При старте backend автоматически выполняет `alembic upgrade head`.

## Локальный запуск без Docker
```bash
cd /Users/macuser/Desktop/Nova.ai/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
export $(grep -v '^#' .env | xargs)
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Основные endpoints
- `GET /health`
- `POST /users` — upsert пользователя по `firebase_uid`
- `GET /users/{firebase_uid}`
- `POST /users/{firebase_uid}/chats`
- `GET /users/{firebase_uid}/chats`
- `POST /chats/{chat_id}/messages`

## Тесты
```bash
cd /Users/macuser/Desktop/Nova.ai/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
```

## Схема
- `users`: лимиты, подписка, поля админ-статуса
- `chats`: чат-сессии пользователя
- `messages`: сообщения в чате
