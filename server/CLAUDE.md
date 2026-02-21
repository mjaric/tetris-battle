# CLAUDE.md — Server (Elixir/Phoenix)

## Prerequisites

- Elixir ~> 1.18 with Erlang/OTP 27
- PostgreSQL 18 (pgvector image used in dev/CI via Docker Compose)

## Development Commands

```bash
mix setup                    # Install deps + create DB + migrate
mix phx.server               # Start dev server on :4000
mix test                     # Run all tests
mix test test/tetris/board_test.exs        # Single test file
mix test test/tetris/board_test.exs:42     # Single test at line
mix format                   # Format all code
mix credo --strict           # Lint (strict mode, max line 120)
```

### Bot Weight Evolution

```bash
mix bot.evolve               # Solo mode — evolve 8-weight heuristic
mix bot.evolve.battle        # Battle mode — evolve 14-weight heuristic (4-player sim)
```

Both tasks support `--population`, `--generations`, `--concurrency`, `--workers` (distributed), and more. Run `mix help bot.evolve` or `mix help bot.evolve.battle` for full options.

## Dependencies

All deps are fetched from Hex (pinned in `mix.lock`). Key libraries:

| Dependency | Purpose | Docs |
|---|---|---|
| phoenix ~> 1.8 | Web framework, channels, PubSub | https://hexdocs.pm/phoenix |
| ecto_sql ~> 3.12 | Database wrapper and query language | https://hexdocs.pm/ecto_sql |
| postgrex ~> 0.20 | PostgreSQL driver | https://hexdocs.pm/postgrex |
| jose ~> 1.11 | JWT signing/verification (HS256) | https://hexdocs.pm/jose |
| ueberauth ~> 0.10 | OAuth authentication framework | https://hexdocs.pm/ueberauth |
| ueberauth_google ~> 0.12 | Google OAuth strategy | https://hexdocs.pm/ueberauth_google |
| ueberauth_github ~> 0.8 | GitHub OAuth strategy | https://hexdocs.pm/ueberauth_github |
| ueberauth_discord ~> 0.7 | Discord OAuth strategy | https://hexdocs.pm/ueberauth_discord |
| jason ~> 1.4 | JSON encoding/decoding | https://hexdocs.pm/jason |
| plug_cowboy ~> 2.8 | Cowboy HTTP adapter for Plug | https://hexdocs.pm/plug_cowboy |
| corsica ~> 2.1 | CORS middleware | https://hexdocs.pm/corsica |
| plug ~> 1.19 | HTTP pipeline | https://hexdocs.pm/plug |
| plug_crypto ~> 2.1 | HMAC, signing, encryption | https://hexdocs.pm/plug_crypto |
| phoenix_pubsub ~> 2.2 | Distributed PubSub | https://hexdocs.pm/phoenix_pubsub |
| phoenix_template ~> 1.0 | Template rendering | https://hexdocs.pm/phoenix_template |
| websock_adapter ~> 0.5 | WebSocket adapter | https://hexdocs.pm/websock_adapter |
| telemetry ~> 1.3 | Instrumentation | https://hexdocs.pm/telemetry |
| telemetry_metrics ~> 1.1 | Metrics definitions | https://hexdocs.pm/telemetry_metrics |
| telemetry_poller ~> 1.3 | Periodic telemetry events | https://hexdocs.pm/telemetry_poller |
| cowboy_telemetry ~> 0.4 | Cowboy telemetry integration | https://hexdocs.pm/cowboy_telemetry |
| castore ~> 1.0 | CA certificate store | https://hexdocs.pm/castore |
| credo ~> 1.7 | Static analysis (dev/test only) | https://hexdocs.pm/credo |
| tidewave ~> 0.5 | MCP server for dev tooling (dev only) | https://hexdocs.pm/tidewave |

When adding a new dependency, use tidewave MCP tools to explore its API if the Phoenix server is running. If tidewave is not available, ask the user to start the server with `mix phx.server` so tidewave tools become accessible. For dependencies not yet installed, consult `mcp__tidewave__search_package_docs`, and/or `mcp__context7__resolve-library-id`, and/or `mcp__context7__query-docs` tools and if you can't find it there, then simply us the docs in https://hexdocs.pm/{package_name}.

## Project Structure

```
lib/
  platform/                # Cross-cutting platform concerns
    accounts.ex            # User context (CRUD, upsert, search)
    accounts/
      user.ex              # User Ecto schema (binary_id PK)
    auth/
      token.ex             # JWT signing/verification (HS256)
    repo.ex                # Ecto Repo (PostgreSQL)
  platform_web/            # Platform HTTP controllers
    controllers/
      auth_controller.ex   # OAuth callbacks, guest login, token refresh
  tetris/                  # Pure game logic (no side effects)
    application.ex         # OTP application & supervision tree
    board.ex               # Board operations (place, clear, collision)
    board_analysis.ex      # 8-metric board evaluation for bot AI
    bot_strategy.ex        # Placement scoring (solo: 8 weights, battle: 14 weights)
    game_logic.ex          # Move processing, gravity, line clearing
    piece.ex               # Tetromino definitions, rotations
    player_state.ex        # Per-player state struct
    wall_kicks.ex          # SRS wall kick data
  tetris_game/             # Stateful OTP processes
    bot_names.ex           # Random bot name generation
    bot_player.ex          # AI player GenServer
    bot_supervisor.ex      # DynamicSupervisor for bot processes
    game_room.ex           # Per-room game engine (GenServer, 50ms tick)
    lobby.ex               # Room registry (GenServer)
    room_supervisor.ex     # DynamicSupervisor for game rooms
  tetris_web/              # Network boundary (Phoenix)
    channels/
      game_channel.ex      # game:{room_id} — input handling, state broadcast
      lobby_channel.ex     # lobby:main — room listing, creation, join
      user_socket.ex       # WebSocket entry point (JWT auth)
    controllers/
      error_json.ex
      page_controller.ex
    plugs/
      cors_plug.ex         # CORS configuration
    endpoint.ex
    router.ex
    telemetry.ex
  bot_trainer/             # Genetic algorithm for bot weight evolution
    battle_simulation.ex   # 4-player battle fitness evaluation
    cluster.ex             # Distributed Erlang cluster management
    evolution.ex           # GA core (selection, crossover, mutation)
    simulation.ex          # Solo game fitness evaluation
  mix/tasks/
    bot.evolve.ex          # mix bot.evolve task
    bot.evolve.battle.ex   # mix bot.evolve.battle task
test/
  platform/                # Tests for accounts and auth
  platform_web/controllers/# Auth controller tests
  tetris/                  # Unit tests for pure game logic
  tetris_game/             # Tests for OTP processes (rooms, lobby, bots)
  tetris_web/channels/     # Channel integration tests
  support/
    channel_case.ex        # Test helper for channel tests
    conn_case.ex           # Test helper for controller tests
    data_case.ex           # Test helper for Ecto tests
config/
  config.exs               # Shared config (PubSub, JSON, Ueberauth, Ecto)
  dev.exs                  # Dev: port 4000, no origin check, local DB
  test.exs                 # Test: port 4002, server disabled, sandbox pool
  prod.exs                 # Prod: host/port from env
  runtime.exs              # Runtime config (DATABASE_URL, OAuth creds, etc.)
```

## Architecture Notes

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

### Module Boundaries

- **`Platform.*`** — User accounts, authentication (Ecto schemas, JWT tokens). Database-backed.
- **`PlatformWeb.*`** — HTTP controllers for auth (OAuth callbacks, guest login, token refresh).
- **`Tetris.*`** — Pure functions, no GenServer calls, no side effects. Safe to call from anywhere.
- **`TetrisGame.*`** — OTP processes. Interact via GenServer calls/casts.
- **`TetrisWeb.*`** — Phoenix layer. Channels handle WebSocket messages, delegate to `TetrisGame`.

### GameRoom Tick Loop (50ms / 20 FPS)

Each tick: drain input queue -> apply moves via `GameLogic` -> apply gravity -> distribute garbage -> check eliminations -> broadcast state.

### Key Patterns

- `PlayerState.to_game_logic_map/1` and `from_game_logic_map/2` bridge the `%PlayerState{}` struct and the plain map used by `GameLogic`.
- Room auth uses HMAC-SHA256 challenge-response (nonce-based, no plaintext passwords over wire).
- All game state broadcasts go through `Phoenix.Channel.broadcast/3` on `game:{room_id}`.
- User auth uses JWT (HS256, key derived from `secret_key_base`). WebSocket connections require a valid JWT token. JWT includes `sub` (user_id) and `name` (display_name) claims.
- OAuth login via Ueberauth (Google, GitHub, Discord) redirects to `/auth/callback#token=JWT`.
- Guest login via `POST /api/auth/guest` creates an anonymous user and returns a JWT.
- Token refresh via `POST /api/auth/refresh` with `Authorization: Bearer <token>`.

## Configuration

### Dev (defaults in `dev.exs`)

Dev requires a running PostgreSQL instance (Docker Compose recommended). Default DB credentials: `postgres`/`password`, database `tetris_dev`. OAuth provider credentials are optional in dev — set them as environment variables if you want to test OAuth login:

| Env Var | Purpose |
|---|---|
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret |
| `GITHUB_CLIENT_ID` | GitHub OAuth client ID |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth client secret |
| `DISCORD_CLIENT_ID` | Discord OAuth client ID |
| `DISCORD_CLIENT_SECRET` | Discord OAuth client secret |

### Prod (set in `runtime.exs`)

| Env Var | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | PostgreSQL connection URL |
| `SECRET_KEY_BASE` | yes | Phoenix secret (also used to derive JWT signing key) |
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

## Code Style

- Max line length: 120 characters (`.formatter.exs` and `.credo.exs`)
- Max function length: 100 lines (Credo check)
- Credo strict mode is enabled
- Run `mix format` before committing
- Run `mix credo --strict` to check for style/design issues
