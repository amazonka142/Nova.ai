# Nova.ai Backend (PostgreSQL + SQLAlchemy)

A minimal backend for migrating from Firestore to a relational database.
Минимальный backend для перехода с Firestore на реальную реляционную БД.

## Stack / Стек
- PostgreSQL
- SQLAlchemy 2.0
- Alembic
- FastAPI
- Firebase Admin SDK (JWT verification)

## Quick Start (Docker) / Быстрый старт (Docker)
Run commands from the repository root (`/Users/macuser/Desktop/Nova.ai`).
Команды выполняются из корня репозитория (`/Users/macuser/Desktop/Nova.ai`).

1. Copy environment variables / Скопировать переменные:
   ```bash
   cp .env.example .env
   ```
   Add Firebase Admin credentials for bearer-token verification:
   / Добавьте Firebase Admin credentials для проверки bearer-токенов.
2. Start services / Поднять сервисы:
   ```bash
   docker compose up --build
   ```
3. Health check / Проверка health:
   - [http://localhost:8000/health](http://localhost:8000/health)

On startup, backend automatically runs `alembic upgrade head`.
При старте backend автоматически выполняет `alembic upgrade head`.

## Local Run Without Docker / Локальный запуск без Docker
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

Authentication / Аутентификация:
- All endpoints except `GET /health` require `Authorization: Bearer <Firebase ID token>`.
- Все endpoint'ы кроме `GET /health` требуют `Authorization: Bearer <Firebase ID token>`.
- Regular users can only access their own `firebase_uid`.
- Обычный пользователь может работать только со своим `firebase_uid`.
- Admin-only user fields (`is_pro`, `is_max`, limits, notes) are accepted only when the decoded token has custom claim `admin=true`.
- Админские поля пользователя (`is_pro`, `is_max`, лимиты, заметки) принимаются только если в токене есть custom claim `admin=true`.

## Main Endpoints / Основные endpoints
- `GET /health`
- `POST /users` — upsert user by `firebase_uid` / upsert пользователя по `firebase_uid`
- `GET /users/{firebase_uid}`
- `POST /users/{firebase_uid}/chats`
- `GET /users/{firebase_uid}/chats?limit=50&offset=0`
- `POST /chats/{chat_id}/messages`
- `GET /chats/{chat_id}/messages?limit=100&offset=0`
- `MessageRead.image_data_base64` is returned for image messages / для image-сообщений возвращается `MessageRead.image_data_base64`

## Tests / Тесты
```bash
cd /Users/macuser/Desktop/Nova.ai/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
```

## Data Model / Схема
- `users`: limits, subscription, admin flags / лимиты, подписка, поля админ-статуса
- `chats`: user chat sessions / чат-сессии пользователя
- `messages`: chat messages / сообщения в чате
