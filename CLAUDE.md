# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multiplayer Tetris battle game. React frontend + Elixir/Phoenix backend communicating over WebSocket channels. Server-authoritative: all game logic runs server-side, clients send inputs and render state.

## Development Commands

### Client (React/TypeScript, in `client/`)

```bash
cd client && npm install       # Install dependencies
cd client && npm run dev       # Vite dev server on :3000
cd client && npm run build     # TypeScript check + Vite production build
cd client && npm run lint      # OxLint
cd client && npm run format    # Prettier (write)
cd client && npm run format:check  # Prettier (check only)
```

### Server (Elixir/Phoenix, in `server/`)

```bash
cd server && mix setup           # Install deps + create DB + migrate
cd server && mix phx.server      # Dev server on :4000
cd server && mix test            # Run all tests
cd server && mix test test/tetris/board_test.exs        # Single test file
cd server && mix test test/tetris/board_test.exs:42     # Single test (line)
cd server && mix format          # Format code
cd server && mix credo --strict  # Lint
```

### Running Both

Start the Phoenix server (port 4000) and Vite dev server (port 3000) simultaneously. The client connects to `ws://localhost:4000/socket`.

## Available MCP Tools

Two MCP tool sets are available for looking up library documentation:

### context7 (general — works for any language/framework)

Use `mcp__context7__resolve-library-id` to find a library ID, then `mcp__context7__query-docs` to query its docs. Works for both client (React, Vite, Tailwind, etc.) and server (Phoenix, Plug, etc.) dependencies — useful when tidewave is not running or for non-Elixir deps.

### tidewave (Elixir-specific — requires running Phoenix server)

Use `mcp__tidewave__get_docs`, `mcp__tidewave__get_source_location`, `mcp__tidewave__project_eval`, `mcp__tidewave__search_package_docs`, and `mcp__tidewave__get_logs` for Elixir/Phoenix work. These only work when the Phoenix dev server is running (`mix phx.server`). If tidewave tools fail, ask the user to start the server.

For dependencies not yet installed, consult https://hexdocs.pm/{package_name} via `WebFetch` or use context7 tools.

## Architecture

### Server-Authoritative Model

Clients send keyboard inputs via WebSocket. The server validates and processes all moves, then broadcasts complete game state to all players every 50ms (20 FPS tick loop). No game rules exist on the frontend.

### Supervision Tree

```
Tetris.Supervisor (one_for_one)
├── Platform.Repo (Ecto — PostgreSQL)
├── TetrisWeb.Telemetry
├── Phoenix.PubSub (name: Tetris.PubSub)
├── Registry (TetrisGame.RoomRegistry, :unique)
├── TetrisGame.RoomSupervisor (DynamicSupervisor)
├── TetrisGame.Lobby (GenServer — room registry)
└── TetrisWeb.Endpoint
```

Each game room is a `TetrisGame.GameRoom` GenServer spawned under `RoomSupervisor`, registered via `TetrisGame.RoomRegistry`.

### Server Module Layers

- **`Platform.*`** — User accounts and authentication: `Accounts` (user CRUD/upsert), `Auth.Token` (JWT HS256), `Repo` (Ecto/PostgreSQL)
- **`PlatformWeb.*`** — HTTP controllers: `AuthController` (OAuth callbacks, guest login, token refresh)
- **`Tetris.*`** — Pure game logic (no side effects): `Piece`, `Board`, `WallKicks`, `GameLogic`, `PlayerState`, `BoardAnalysis` (8-metric board evaluation), `BotStrategy` (placement scoring for solo 8-weight and battle 14-weight modes)
- **`TetrisGame.*`** — Stateful processes: `Lobby` (room registry), `GameRoom` (per-room engine), `RoomSupervisor`
- **`TetrisWeb.*`** — Network boundary: `LobbyChannel` (`lobby:main`), `GameChannel` (`game:{room_id}`), `UserSocket` (JWT auth), `Endpoint`

### Client Structure

- **Auth** — `AuthProvider` (JWT context + localStorage), `LoginScreen` (OAuth + guest), `AuthCallback` (OAuth redirect handler), `useAuth` (login/logout actions)
- **Components** — `MainMenu`, `Lobby`, `WaitingRoom`, `MultiBoard`, `PlayerBoard`, `Board`, `Results`, `TargetIndicator`, `Sidebar`, `NextPiece`, `SoloGame`, `GameSession`
- **Hooks** — `useTetris` (solo, client-only game loop), `useSocket`/`useChannel` (Phoenix connection lifecycle), `useMultiplayerGame` (MP state + input dispatch), `useAnimations`, `useSoundEffects`, `useGameEvents`, `useLatency`
- **`App.tsx`** — React Router with auth guards: `/login` → `/` (MainMenu) → `/solo` | `/lobby` → `/room/:roomId`

### Authentication

- **OAuth providers**: Google, GitHub, Discord via Ueberauth. Browser redirects to `/auth/:provider`, callback redirects back to client with JWT in URL hash fragment.
- **Guest login**: `POST /api/auth/guest` creates an anonymous user and returns a JWT.
- **Token refresh**: `POST /api/auth/refresh` with `Authorization: Bearer <token>`.
- **WebSocket auth**: Client sends JWT as socket param. `UserSocket` verifies token and extracts user info.
- **JWT claims**: `sub` (user_id), `name` (display_name), `iat`, `exp`. HS256 signed with key derived from `secret_key_base`.

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

- Server dependencies are fetched from Hex (pinned in `mix.lock`)
- Client dependencies are from npm (`package-lock.json`)
- PostgreSQL required — user accounts stored in `Platform.Repo` (dev default: `postgres`/`password`, database `tetris_dev`)
- `PlayerState.to_game_logic_map/1` and `from_game_logic_map/2` bridge the struct/map boundary between `PlayerState` and `GameLogic`
- Solo mode runs entirely client-side via `useTetris` hook — no server involvement
- Piece definitions and SRS wall kick data are duplicated between client (`constants.ts`) and server (`Piece`, `WallKicks` modules)
- Board dimensions: 10 wide x 20 tall (standard Tetris)
- Test port: 4002 (server disabled in test config)
- Client env var `VITE_API_URL` overrides the API server URL (default: `http://localhost:4000`)
