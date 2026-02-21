# Tetris

Multiplayer Tetris battle game. React frontend + Elixir/Phoenix backend communicating over WebSocket channels.

## Architecture

Server-authoritative: all game logic runs server-side, clients send inputs and render state. The server broadcasts complete game state to all players every 50ms (20 FPS tick loop).

```
client/    React frontend (Vite + React + Tailwind)
server/    Elixir/Phoenix backend (port 4000)
docs/      Project documentation and notes
```

## Prerequisites

- Elixir ~> 1.18 with Erlang/OTP 27
- Node.js 22
- PostgreSQL 18 (Docker Compose recommended)

## Quick Start

```bash
# Start PostgreSQL (if using Docker Compose)
docker compose up -d

# Install dependencies, create DB, migrate, and start the server
cd server && npm install --prefix ../client && mix setup && mix phx.server
```

`mix phx.server` starts the Phoenix server on port 4000 and automatically builds the client (Vite watch mode). Open `http://localhost:4000`.

Alternatively, run the client dev server separately for HMR:

```bash
cd server && mix phx.server      # Terminal 1 — backend on :4000
cd client && npm run dev          # Terminal 2 — Vite HMR on :3000
```

## Authentication

Login via OAuth (Google, GitHub, Discord) or as a guest. Guest accounts require no configuration.

### OAuth Setup (optional)

To enable OAuth login, register an app with each provider and set the environment variables before starting the server:

| Variable | Provider | Where to register |
|---|---|---|
| `GOOGLE_CLIENT_ID` | Google | [Google Cloud Console](https://console.cloud.google.com/apis/credentials) |
| `GOOGLE_CLIENT_SECRET` | Google | |
| `GITHUB_CLIENT_ID` | GitHub | [GitHub Developer Settings](https://github.com/settings/developers) |
| `GITHUB_CLIENT_SECRET` | GitHub | |
| `DISCORD_CLIENT_ID` | Discord | [Discord Developer Portal](https://discord.com/developers/applications) |
| `DISCORD_CLIENT_SECRET` | Discord | |

Set the OAuth callback URL for each provider to:

```
http://localhost:4000/auth/<provider>/callback
```

Where `<provider>` is `google`, `github`, or `discord`.

### Production Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | PostgreSQL connection URL |
| `SECRET_KEY_BASE` | yes | Phoenix secret (also derives JWT signing key) |
| `PHX_HOST` | yes | Public hostname |
| `CLIENT_URL` | yes | Frontend URL for OAuth redirects |
| `PORT` | no | HTTP port (default: 4000) |
| `POOL_SIZE` | no | Database pool size (default: 10) |
| `CORS_ORIGINS` | no | Comma-separated allowed origins |
| `GOOGLE_CLIENT_ID` | no | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | no | Google OAuth client secret |
| `GITHUB_CLIENT_ID` | no | GitHub OAuth client ID |
| `GITHUB_CLIENT_SECRET` | no | GitHub OAuth client secret |
| `DISCORD_CLIENT_ID` | no | Discord OAuth client ID |
| `DISCORD_CLIENT_SECRET` | no | Discord OAuth client secret |

## Game Modes

- **Solo** — client-side only via `useTetris` hook, no server involvement
- **Multiplayer** — server-authoritative rooms with bot players (Easy/Medium/Hard difficulty)

## Bot Training

The Hard bot's heuristic weights are evolved via genetic algorithm. The GA simulates thousands of headless games with pruned 2-piece lookahead, selecting weight vectors that maximize average lines cleared.

```bash
cd server
mix bot.evolve --population 50 --generations 100 --games 30
```

Supports distributed evaluation across multiple BEAM nodes. See `docs/notes/bot-evolution.md`.

## Documentation

- `docs/notes/bot-evolution.md` — GA pipeline, distributed training, all options
- `docs/notes/bot-performance.md` — Bot strengths, weaknesses, improvement roadmap
- `docs/notes/run-notes.md` — Evolution run observations and optimization history
