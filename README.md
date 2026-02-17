# Tetris

Multiplayer Tetris battle game. React frontend + Elixir/Phoenix backend communicating over WebSocket channels.

## Architecture

Server-authoritative: all game logic runs server-side, clients send inputs and render state. The server broadcasts complete game state to all players every 50ms (20 FPS tick loop).

```
client/    React frontend (port 3000)
server/    Elixir/Phoenix backend (port 4000)
docs/      Project documentation and notes
```

## Quick Start

```bash
# Server
cd server && mix setup && mix phx.server

# Client (separate terminal)
cd client && npm install && npm start
```

The client connects to `ws://localhost:4000/socket` (configurable via `REACT_APP_SOCKET_URL`).

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
