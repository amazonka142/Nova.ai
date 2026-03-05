# Nova.ai

[![Built with Pollinations](https://img.shields.io/badge/Built%20with-Pollinations-8a2be2?style=for-the-badge&logo=data:image/svg+xml,%3Csvg%20xmlns%3D%22http://www.w3.org/2000/svg%22%20viewBox%3D%220%200%20124%20124%22%3E%3Ccircle%20cx%3D%2262%22%20cy%3D%2262%22%20r%3D%2262%22%20fill%3D%22%23ffffff%22/%3E%3C/svg%3E&logoColor=white&labelColor=6a0dad)](https://pollinations.ai)

![pollinations.ai logo](https://raw.githubusercontent.com/pollinations/pollinations/main/assets/logo.svg)

Nova.ai is an iOS AI assistant app for chat, reasoning, and image generation.

## Pollinations.ai Integration

Nova.ai uses pollinations.ai APIs in two core flows:

- Text generation and chat via `https://gen.pollinations.ai/v1/chat/completions`
- Image generation via `https://gen.pollinations.ai/image/{prompt}?model=flux`

## Installation and Run

### Requirements

- macOS with Xcode installed
- iOS Simulator or physical iPhone
- (Optional) Docker for backend
- (Optional) Python 3.11+ for backend without Docker

### iOS app setup

1. Open the project:
   ```bash
   open Nova.ai.xcodeproj
   ```
2. Configure app keys in `Nova-ai-Info.plist` (at minimum `POLLINATIONS_API_KEY`).
3. If you use Firebase, copy and configure:
   ```bash
   cp GoogleService-Info.plist.example Nova.ai/GoogleService-Info.plist
   ```
4. In Xcode, select the `Nova.ai` scheme and run (`Cmd+R`).

### Backend setup (optional)

Run from repository root:

```bash
cp .env.example .env
docker compose up --build
```

Health check:

- [http://localhost:8000/health](http://localhost:8000/health)

Detailed backend instructions: [backend/README.md](backend/README.md)

## Features

- Multi-model AI chat
- Streaming responses
- Image prompt generation and gallery
- Image input support in chat
- Project-based chat organization

## Credits

Built with [pollinations.ai](https://pollinations.ai).

App author (GitHub): [@amazonka142](https://github.com/amazonka142)
