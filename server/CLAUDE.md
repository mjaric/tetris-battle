# CLAUDE.md — Server (Elixir/Phoenix)

## Prerequisites

- Elixir ~> 1.18 with Erlang/OTP 27
- No database required — all state is in-memory (GenServers, ETS)

## Development Commands

```bash
mix setup                    # Install dependencies (alias for deps.get)
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
      user_socket.ex       # WebSocket entry point
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
  tetris/                  # Unit tests for pure game logic
  tetris_game/             # Tests for OTP processes (rooms, lobby, bots)
  tetris_web/channels/     # Channel integration tests
  support/
    channel_case.ex        # Test helper for channel tests
config/
  config.exs               # Shared config (PubSub, JSON library)
  dev.exs                  # Dev: port 4000, no origin check
  test.exs                 # Test: port 4002, server disabled
  prod.exs                 # Prod: host/port from env
  runtime.exs              # Runtime config (SECRET_KEY_BASE, PHX_HOST, CORS_ORIGINS)
```

## Architecture Notes

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

### Module Boundaries

- **`Tetris.*`** — Pure functions, no GenServer calls, no side effects. Safe to call from anywhere.
- **`TetrisGame.*`** — OTP processes. Interact via GenServer calls/casts.
- **`TetrisWeb.*`** — Phoenix layer. Channels handle WebSocket messages, delegate to `TetrisGame`.

### GameRoom Tick Loop (50ms / 20 FPS)

Each tick: drain input queue -> apply moves via `GameLogic` -> apply gravity -> distribute garbage -> check eliminations -> broadcast state.

### Key Patterns

- `PlayerState.to_game_logic_map/1` and `from_game_logic_map/2` bridge the `%PlayerState{}` struct and the plain map used by `GameLogic`.
- Room auth uses HMAC-SHA256 challenge-response (nonce-based, no plaintext passwords over wire).
- All game state broadcasts go through `Phoenix.Channel.broadcast/3` on `game:{room_id}`.

## Configuration

| Env Var | Used In | Purpose |
|---|---|---|
| `SECRET_KEY_BASE` | prod runtime | Phoenix secret (required) |
| `PHX_HOST` | prod runtime | Public hostname (required) |
| `PORT` | prod runtime | HTTP port (default: 4000) |
| `CORS_ORIGINS` | prod runtime | Comma-separated allowed origins |

## Code Style

- Max line length: 120 characters (`.formatter.exs` and `.credo.exs`)
- Max function length: 100 lines (Credo check)
- Credo strict mode is enabled
- Run `mix format` before committing
- Run `mix credo --strict` to check for style/design issues
