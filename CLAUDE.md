# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multiplayer Tetris battle game. React frontend + Elixir/Phoenix backend communicating over WebSocket channels. Server-authoritative: all game logic runs server-side, clients send inputs and render state.

## Development Commands

### Client (React, in `client/`)

```bash
cd client && npm start          # Dev server on :3000
cd client && npm test            # Jest in watch mode
cd client && npm test -- --watchAll=false  # Jest single run
cd client && npm run build       # Production build
```

### Server (Elixir/Phoenix, in `server/`)

```bash
cd server && mix setup           # Install deps
cd server && mix phx.server      # Dev server on :4000
cd server && mix test            # Run all tests
cd server && mix test test/tetris/board_test.exs        # Single test file
cd server && mix test test/tetris/board_test.exs:42     # Single test (line)
```

### Running Both

Start the Phoenix server (port 4000) and React dev server (port 3000) simultaneously. The client connects to `ws://localhost:4000/socket` (configurable via `REACT_APP_SOCKET_URL`).

## Architecture

### Server-Authoritative Model

Clients send keyboard inputs via WebSocket. The server validates and processes all moves, then broadcasts complete game state to all players every 50ms (20 FPS tick loop). No game rules exist on the frontend.

### Supervision Tree

```
Tetris.Supervisor (one_for_one)
├── TetrisWeb.Telemetry
├── Phoenix.PubSub (name: Tetris.PubSub)
├── Registry (TetrisGame.RoomRegistry, :unique)
├── TetrisGame.RoomSupervisor (DynamicSupervisor)
├── TetrisGame.Lobby (GenServer — room registry)
└── TetrisWeb.Endpoint
```

Each game room is a `TetrisGame.GameRoom` GenServer spawned under `RoomSupervisor`, registered via `TetrisGame.RoomRegistry`.

### Server Module Layers

- **`Tetris.*`** — Pure game logic (no side effects): `Piece`, `Board`, `WallKicks`, `GameLogic`, `PlayerState`
- **`TetrisGame.*`** — Stateful processes: `Lobby` (room registry), `GameRoom` (per-room engine), `RoomSupervisor`
- **`TetrisWeb.*`** — Network boundary: `LobbyChannel` (`lobby:main`), `GameChannel` (`game:{room_id}`), `UserSocket`, `Endpoint`

### Client Structure

- **Components** — `MainMenu`, `NicknameForm`, `Lobby`, `WaitingRoom`, `MultiBoard`, `MiniBoard`, `Board`, `Results`, `TargetIndicator`, `Sidebar`, `NextPiece`
- **Hooks** — `useTetris` (solo, client-only game loop), `useSocket`/`useChannel` (Phoenix connection lifecycle), `useMultiplayerGame` (MP state + input dispatch)
- **`App.js`** — Screen state machine: `menu → solo | nickname → lobby → waiting → playing → results`

### Client-Server Protocol

- **Channels**: `lobby:main` (shared) and `game:{room_id}` (per-room)
- **Client → Server**: `"input"` with `action` (move_left/move_right/move_down/rotate/hard_drop), `"set_target"`, `"start_game"`
- **Server → Client**: `"game_state"` broadcast (all players' boards, scores, status, eliminations)
- **Room auth**: HMAC-SHA256 challenge-response for password-protected rooms (nonce-based, no plaintext)

### Game Tick Loop (GameRoom, 50ms)

1. Drain each player's input queue → apply via `GameLogic`
2. Apply gravity (piece falls based on level)
3. Distribute garbage (cleared lines → garbage rows to target)
4. Check eliminations (board overflow)
5. Broadcast state to all clients

### Garbage Mechanics

Clear N lines → send (N-1) garbage rows to targeted opponent (only for N >= 2). Garbage rows are full with one random gap. Queued in `pending_garbage`, inserted when opponent's piece locks. Tab key cycles through alive opponents.

## Key Conventions

- All dependencies in `server/mix.exs` are pinned to git tags with `override: true` (no Hex)
- `PlayerState.to_game_logic_map/1` and `from_game_logic_map/2` bridge the struct↔map boundary between `PlayerState` and `GameLogic`
- Solo mode runs entirely client-side via `useTetris` hook — no server involvement
- Piece definitions and SRS wall kick data are duplicated between client (`constants.js`) and server (`Piece`, `WallKicks` modules)
- Board dimensions: 10 wide × 20 tall (standard Tetris)
- Test port: 4002 (server disabled in test config)
