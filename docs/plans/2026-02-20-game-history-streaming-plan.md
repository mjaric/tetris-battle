# Game History & Event Streaming — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add match history with NATS JetStream event streaming, heuristic key moment detection, solo stats reporting, and match history UI.

**Architecture:** Game events published to NATS JetStream during tick loop. Two consumers: Match Projector (projects game results to Postgres) and Key Moment Detector (detects moments, publishes back to same stream). JetStream is the event store (90-day retention). Postgres stores match metadata and player stats as permanent read-model projections.

**Tech Stack:** Gnat (NATS client), Ecto (existing from Auth plan)

**Design doc:** `docs/plans/2026-02-20-game-history-streaming-design.md`

**Depends on:** Auth & Registration plan — needs user IDs, Ecto repo, JWT verification

---

## Task 1: Match History Schema and Context

**Files:**
- Create: `server/priv/repo/migrations/*_create_matches.exs`
- Create: `server/lib/platform/history/match.ex`
- Create: `server/lib/platform/history/match_player.ex`
- Create: `server/lib/platform/history.ex`
- Create: `server/test/platform/history_test.exs`

**Step 1: Generate and write migration**

Run: `cd server && mix ecto.gen.migration create_matches`

```elixir
defmodule Platform.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_type, :text, null: false, default: "tetris"
      add :room_id, :text
      add :mode, :text, null: false
      add :player_count, :integer
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:match_players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :match_id, references(:matches, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :placement, :integer
      add :score, :integer
      add :lines_cleared, :integer
      add :garbage_sent, :integer
      add :garbage_received, :integer
      add :pieces_placed, :integer
      add :duration_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:match_players, [:match_id])
    create index(:match_players, [:user_id])
  end
end
```

No `replay_events` table — JetStream is the event store per design doc.

**Step 2: Write Ecto schemas**

Create `server/lib/platform/history/match.ex`:

```elixir
defmodule Platform.History.Match do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "matches" do
    field :game_type, :string, default: "tetris"
    field :room_id, :string
    field :mode, :string
    field :player_count, :integer
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    has_many :match_players, Platform.History.MatchPlayer

    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [:game_type, :room_id, :mode, :player_count, :started_at, :ended_at])
    |> validate_required([:mode])
    |> validate_inclusion(:mode, ["multiplayer", "solo"])
  end
end
```

Create `server/lib/platform/history/match_player.ex`:

```elixir
defmodule Platform.History.MatchPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_players" do
    belongs_to :match, Platform.History.Match
    belongs_to :user, Platform.Accounts.User

    field :placement, :integer
    field :score, :integer
    field :lines_cleared, :integer
    field :garbage_sent, :integer
    field :garbage_received, :integer
    field :pieces_placed, :integer
    field :duration_ms, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(mp, attrs) do
    mp
    |> cast(attrs, [
      :match_id, :user_id, :placement, :score, :lines_cleared,
      :garbage_sent, :garbage_received, :pieces_placed, :duration_ms
    ])
    |> validate_required([:match_id])
  end
end
```

**Step 3: Write History context**

Create `server/lib/platform/history.ex`:

```elixir
defmodule Platform.History do
  @moduledoc """
  Context for querying match history projections in Postgres.

  Matches and player stats are projected from game events by the
  MatchProjector consumer. This context provides read-only queries
  over those projections plus a `record_match/1` function used by
  the projector and the solo results endpoint.
  """

  import Ecto.Query
  alias Platform.Repo
  alias Platform.History.{Match, MatchPlayer}

  def record_match(attrs) do
    Repo.transaction(fn ->
      {:ok, match} =
        %Match{}
        |> Match.changeset(Map.drop(attrs, [:players]))
        |> Repo.insert()

      if attrs[:players] do
        Enum.each(attrs.players, fn player_attrs ->
          {:ok, _} =
            %MatchPlayer{}
            |> MatchPlayer.changeset(Map.put(player_attrs, :match_id, match.id))
            |> Repo.insert()
        end)
      end

      match
    end)
  end

  def list_matches(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(m in Match,
      join: mp in MatchPlayer,
      on: mp.match_id == m.id,
      where: mp.user_id == ^user_id,
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:match_players]
    )
    |> Repo.all()
  end

  def get_match(match_id) do
    case Repo.get(Match, match_id) do
      nil -> {:error, :not_found}
      match -> {:ok, Repo.preload(match, [:match_players])}
    end
  end
end
```

**Step 4: Write tests**

Create `server/test/platform/history_test.exs`:

```elixir
defmodule Platform.HistoryTest do
  use Platform.DataCase, async: true

  alias Platform.Accounts
  alias Platform.History

  setup do
    {:ok, alice} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "hist_alice",
        display_name: "Alice"
      })

    {:ok, bob} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "hist_bob",
        display_name: "Bob"
      })

    %{alice: alice, bob: bob}
  end

  describe "record_match/1" do
    test "records a match with players", %{alice: alice, bob: bob} do
      attrs = %{
        mode: "multiplayer",
        game_type: "tetris",
        room_id: "room_123",
        player_count: 2,
        started_at: DateTime.utc_now() |> DateTime.add(-300) |> DateTime.truncate(:second),
        ended_at: DateTime.utc_now() |> DateTime.truncate(:second),
        players: [
          %{user_id: alice.id, placement: 1, score: 5000, lines_cleared: 20},
          %{user_id: bob.id, placement: 2, score: 3000, lines_cleared: 12}
        ]
      }

      assert {:ok, match} = History.record_match(attrs)
      assert match.mode == "multiplayer"
      assert match.player_count == 2
    end

    test "records a solo match", %{alice: alice} do
      attrs = %{
        mode: "solo",
        player_count: 1,
        players: [
          %{user_id: alice.id, score: 8000, lines_cleared: 40, pieces_placed: 120, duration_ms: 180_000}
        ]
      }

      assert {:ok, match} = History.record_match(attrs)
      assert match.mode == "solo"
    end
  end

  describe "list_matches/2" do
    test "returns matches for a user", %{alice: alice} do
      History.record_match(%{
        mode: "solo",
        player_count: 1,
        players: [%{user_id: alice.id, score: 1000}]
      })

      matches = History.list_matches(alice.id)
      assert length(matches) == 1
    end

    test "paginates results", %{alice: alice} do
      for i <- 1..5 do
        History.record_match(%{
          mode: "solo",
          player_count: 1,
          players: [%{user_id: alice.id, score: i * 1000}]
        })
      end

      page1 = History.list_matches(alice.id, limit: 2, offset: 0)
      page2 = History.list_matches(alice.id, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2
    end

    test "does not return other users' matches", %{alice: alice, bob: bob} do
      History.record_match(%{
        mode: "solo",
        player_count: 1,
        players: [%{user_id: bob.id, score: 1000}]
      })

      assert History.list_matches(alice.id) == []
    end
  end

  describe "get_match/1" do
    test "returns match with players", %{alice: alice} do
      {:ok, match} =
        History.record_match(%{
          mode: "solo",
          player_count: 1,
          players: [%{user_id: alice.id, score: 5000}]
        })

      assert {:ok, fetched} = History.get_match(match.id)
      assert fetched.id == match.id
      assert length(fetched.match_players) == 1
    end

    test "returns error for missing match" do
      assert {:error, :not_found} = History.get_match(Ecto.UUID.generate())
    end
  end
end
```

**Step 5: Run migration and tests**

```bash
cd server && mix ecto.migrate
cd server && mix test test/platform/history_test.exs -v
cd server && mix test
```

**Step 6: Commit**

```bash
git add server/priv/repo/migrations/ server/lib/platform/history/ \
  server/lib/platform/history.ex \
  server/test/platform/history_test.exs
git commit -m "feat: add match history schema and context"
```

---

## Task 2: NATS JetStream Setup

**Files:**
- Modify: `server/mix.exs` (add `gnat` dependency)
- Create: `server/lib/platform/streaming/nats_connection.ex`
- Create: `server/lib/platform/streaming/stream_setup.ex`
- Modify: `server/config/config.exs`
- Modify: `server/config/test.exs`
- Modify: `server/lib/tetris/application.ex`

**Step 1: Add Gnat dependency**

Add to deps in `server/mix.exs`:

```elixir
{:gnat, "~> 1.8"},
```

Run: `cd server && mix deps.get`

**Step 2: Add NATS config**

In `server/config/config.exs`:

```elixir
config :tetris, Platform.Streaming,
  nats_url: "nats://localhost:4222",
  stream_name: "GAME_EVENTS",
  stream_subjects: ["game.>"]
```

In `server/config/test.exs`:

```elixir
config :tetris, Platform.Streaming,
  enabled: false
```

**Step 3: Write NATS connection supervisor**

Create `server/lib/platform/streaming/nats_connection.ex`:

```elixir
defmodule Platform.Streaming.NatsConnection do
  def start_link(_opts) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] == false do
      :ignore
    else
      connection_settings = parse_url(config[:nats_url] || "nats://localhost:4222")
      Gnat.start_link(connection_settings, name: __MODULE__)
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  defp parse_url(url) do
    uri = URI.parse(url)
    %{host: uri.host || "localhost", port: uri.port || 4222}
  end
end
```

**Step 4: Write stream setup module**

Create `server/lib/platform/streaming/stream_setup.ex`:

```elixir
defmodule Platform.Streaming.StreamSetup do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] == false do
      :ignore
    else
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :setup_streams}}
  end

  @impl true
  def handle_continue(:setup_streams, state) do
    config = Application.get_env(:tetris, Platform.Streaming)
    stream_name = config[:stream_name] || "GAME_EVENTS"
    subjects = config[:stream_subjects] || ["game.>"]

    stream_config = %{
      name: stream_name,
      subjects: subjects,
      retention: :limits,
      max_age: 90 * 24 * 60 * 60 * 1_000_000_000,
      storage: :file
    }

    case Gnat.jetstream_create_stream(Platform.Streaming.NatsConnection, stream_config) do
      {:ok, _info} ->
        Logger.info("JetStream stream '#{stream_name}' created/verified")

      {:error, reason} ->
        Logger.warning("JetStream stream setup: #{inspect(reason)}")
    end

    {:noreply, state}
  end
end
```

Note: `retention: :limits` and `max_age: 90 days` per design doc (not `:interest` / 7 days as in old plan).

**Step 5: Add to supervision tree**

In `server/lib/tetris/application.ex`, add before `TetrisWeb.Endpoint`:

```elixir
Platform.Streaming.NatsConnection,
Platform.Streaming.StreamSetup,
```

**Step 6: Run tests**

```bash
cd server && mix test
```

**Step 7: Commit**

```bash
git add server/mix.exs server/mix.lock server/lib/platform/streaming/ \
  server/lib/tetris/application.ex server/config/
git commit -m "feat: add NATS JetStream connection and stream setup"
```

---

## Task 3: Event Publisher and GameRoom Integration

**Files:**
- Create: `server/lib/platform/streaming/event_publisher.ex`
- Modify: `server/lib/tetris_game/game_room.ex`
- Create: `server/test/platform/streaming/event_publisher_test.exs`

**Step 1: Write EventPublisher**

Create `server/lib/platform/streaming/event_publisher.ex`:

```elixir
defmodule Platform.Streaming.EventPublisher do
  def publish(room_id, event) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] != false do
      subject = "game.#{room_id}.events"
      payload = Jason.encode!(event)

      case Gnat.pub(Platform.Streaming.NatsConnection, subject, payload) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def publish_batch(room_id, events) when is_list(events) do
    Enum.each(events, &publish(room_id, &1))
  end
end
```

**Step 2: Modify GameRoom to publish events**

In `server/lib/tetris_game/game_room.ex`:

1. After `broadcast_state(state)` in `process_tick/1` (line ~551), add `publish_events_to_nats(state)`.
2. In the `start_game` handler (after setting status to `:playing`), publish a `game_start` event.
3. Add helper functions:

```elixir
defp publish_events_to_nats(state) do
  # Collect per-player events from this tick
  player_events =
    Enum.flat_map(state.players, fn {player_id, player} ->
      Enum.map(player.events, fn event ->
        %{
          tick: state.tick,
          player_id: player_id,
          type: event.type,
          data: Map.drop(event, [:type])
        }
      end)
    end)

  # Add game_end lifecycle event with full stats per design doc
  lifecycle_events =
    if state.status == :finished do
      player_stats =
        Enum.map(state.players, fn {player_id, player} ->
          alive_players = Enum.count(state.players, fn {_, p} -> p.alive end)
          placement =
            cond do
              player.alive -> 1
              true ->
                eliminated_idx = Enum.find_index(state.eliminated_order, &(&1 == player_id))
                if eliminated_idx, do: map_size(state.players) - eliminated_idx, else: nil
            end

          %{
            player_id: player_id,
            placement: placement,
            score: player.score,
            lines_cleared: player.lines_cleared,
            garbage_sent: player.garbage_sent,
            garbage_received: player.garbage_received,
            pieces_placed: player.pieces_placed,
            duration_ms: player.duration_ms
          }
        end)

      [%{
        tick: state.tick,
        type: "game_end",
        data: %{
          room_id: state.room_id,
          mode: "multiplayer",
          player_count: map_size(state.players),
          eliminated_order: state.eliminated_order,
          players: player_stats,
          started_at: state.started_at,
          ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      }]
    else
      []
    end

  all_events = player_events ++ lifecycle_events

  if all_events != [] do
    Platform.Streaming.EventPublisher.publish_batch(state.room_id, all_events)
  end
end

defp publish_game_start(state) do
  player_list =
    Enum.map(state.players, fn {player_id, player} ->
      %{player_id: player_id, nickname: player.nickname}
    end)

  Platform.Streaming.EventPublisher.publish(state.room_id, %{
    tick: 0,
    type: "game_start",
    data: %{
      room_id: state.room_id,
      players: player_list,
      player_count: map_size(state.players)
    }
  })
end
```

Note: The `game_end` event includes full per-player stats (score, lines_cleared, garbage_sent, garbage_received, pieces_placed, duration_ms, placement) so the MatchProjector can project to Postgres without needing to buffer earlier events. Fields like `started_at`, `duration_ms`, `garbage_sent`, `garbage_received` may need to be added to `PlayerState` if not already tracked — check existing struct and add any missing fields.

**Step 3: Write tests**

Create `server/test/platform/streaming/event_publisher_test.exs`:

```elixir
defmodule Platform.Streaming.EventPublisherTest do
  use ExUnit.Case, async: true

  alias Platform.Streaming.EventPublisher

  test "publish returns :ok when NATS is disabled" do
    event = %{tick: 1, type: "piece_lock", player_id: "p1", data: %{}}
    assert :ok = EventPublisher.publish("room_123", event)
  end

  test "publish_batch returns :ok when NATS is disabled" do
    events = [
      %{tick: 1, type: "piece_lock", player_id: "p1", data: %{}},
      %{tick: 1, type: "line_clear", player_id: "p1", data: %{count: 2}}
    ]

    assert :ok = EventPublisher.publish_batch("room_123", events)
  end
end
```

**Step 4: Run tests**

```bash
cd server && mix test
```

**Step 5: Commit**

```bash
git add server/lib/platform/streaming/event_publisher.ex \
  server/lib/tetris_game/game_room.ex \
  server/test/platform/streaming/
git commit -m "feat: publish game events to NATS JetStream from GameRoom"
```

---

## Task 4: Match Projector and Key Moment Detector Consumers

**Files:**
- Create: `server/lib/platform/streaming/match_projector.ex`
- Create: `server/lib/platform/streaming/key_moment_detector.ex`
- Create: `server/test/platform/streaming/match_projector_test.exs`
- Create: `server/test/platform/streaming/key_moment_detector_test.exs`
- Modify: `server/lib/tetris/application.ex`

**Step 1: Write MatchProjector consumer**

Create `server/lib/platform/streaming/match_projector.ex` — Durable JetStream consumer subscribed to `game.*.events`. On receiving a `game_end` event:

1. Creates a `matches` row with game metadata (mode, room_id, player_count, started_at, ended_at)
2. Creates `match_players` rows with each player's final stats (score, lines_cleared, garbage_sent, garbage_received, pieces_placed, duration_ms, placement)
3. Acknowledges the message

Uses `room_id` + `started_at` as a natural dedup key (idempotent). Returns `:ignore` when NATS disabled.

**Step 2: Write MatchProjector tests**

Create `server/test/platform/streaming/match_projector_test.exs` — unit tests that call the projection logic directly with crafted `game_end` events. Verify correct Postgres writes (match created, match_players created with stats). Test idempotency.

**Step 3: Write KeyMomentDetector consumer**

Create `server/lib/platform/streaming/key_moment_detector.ex` — NATS consumer that detects key moments and publishes them back to `game.{room_id}.moments`. Key moments to detect:

| Moment | Trigger |
|--------|---------|
| `tetris` | 4-line clear |
| `t_spin_single` | T-spin with 1 line |
| `t_spin_double` | T-spin with 2 lines |
| `t_spin_triple` | T-spin with 3 lines |
| `back_to_back` | Consecutive bonus clears |
| `garbage_surge` | 3+ garbage rows sent in sequence |
| `near_death_survival` | Board above row 16, then cleared below row 10 |
| `elimination` | Player eliminated from match |
| `comeback` | Last place to winning |
| `perfect_clear` | Board empty after line clear |

Subscribes only to `.events` subjects — never reads its own `.moments` output (no infinite loop).

Expose `detect_moments/2` as a public function for unit testing with crafted event sequences.

Returns `:ignore` when NATS disabled.

**Step 4: Write KeyMomentDetector tests**

Create `server/test/platform/streaming/key_moment_detector_test.exs` — unit tests for each heuristic with crafted event inputs. Call `detect_moments/2` directly.

**Step 5: Add consumers to supervision tree**

In `server/lib/tetris/application.ex`, add after `Platform.Streaming.StreamSetup`:

```elixir
Platform.Streaming.MatchProjector,
Platform.Streaming.KeyMomentDetector,
```

**Step 6: Run tests**

```bash
cd server && mix test
```

**Step 7: Commit**

```bash
git add server/lib/platform/streaming/ server/lib/tetris/application.ex \
  server/test/platform/streaming/
git commit -m "feat: add match projector and key moment detector NATS consumers"
```

---

## Task 5: Solo Results REST Endpoint

**Files:**
- Create: `server/lib/platform_web/controllers/solo_result_controller.ex`
- Modify: `server/lib/tetris_web/router.ex`
- Create: `server/test/platform_web/controllers/solo_result_controller_test.exs`

**Step 1: Add route to existing router**

In `server/lib/tetris_web/router.ex`, add inside the `/api` scope (or add a new authenticated API scope):

```elixir
scope "/api", PlatformWeb do
  pipe_through :api
  post "/solo_results", SoloResultController, :create
end
```

**Step 2: Create SoloResultController**

Create `server/lib/platform_web/controllers/solo_result_controller.ex`:

- Extracts Bearer token from `Authorization` header
- Verifies via `Platform.Auth.Token.verify/1`
- Finds user via `Platform.Accounts.get_user/1`
- Records match with `mode: "solo"` via `Platform.History.record_match/1`
- Returns `201` with match ID on success
- Returns `401` for invalid/expired/missing token
- Returns `422` for invalid params

**Step 3: Write controller tests**

Create `server/test/platform_web/controllers/solo_result_controller_test.exs`:

- Test with valid JWT → 201, match recorded
- Test with missing token → 401
- Test with expired/invalid token → 401
- Test with missing required params → 422

**Step 4: Run tests**

```bash
cd server && mix test
```

**Step 5: Commit**

```bash
git add server/lib/platform_web/controllers/solo_result_controller.ex \
  server/lib/tetris_web/router.ex \
  server/test/platform_web/controllers/
git commit -m "feat: add solo results REST endpoint"
```

---

## Task 6: Client — Match History UI

**Files:**
- Create: `client/src/platform/history/useHistory.ts`
- Create: `client/src/platform/history/MatchHistory.tsx`
- Modify: `client/src/App.tsx` (add `/history` route)
- Modify: `client/src/components/SoloGame.tsx` (report results when authenticated)

**Step 1: Create useHistory hook**

Fetches match history via REST or channel message. Returns paginated list of matches with player stats. Handle loading and error states.

**Step 2: Create MatchHistory component**

Paginated match list with date, mode, placement, score, lines. Follow existing glassmorphism UI style. Include a link back to main menu.

**Step 3: Modify SoloGame to report results**

On game over, if authenticated, POST to `/api/solo_results` with `Authorization: Bearer <token>`. Send score, lines cleared, pieces placed, and duration. Fire-and-forget — don't block the game over UI on the result.

**Step 4: Add route and verify build**

```bash
cd client && npm run build
```

**Step 5: Commit**

```bash
git add client/src/
git commit -m "feat: add match history UI and solo results reporting"
```

---

## Task 7: Integration Verification

**Step 1: Run all server tests**

```bash
cd server && mix test
```

**Step 2: Run all server checks**

```bash
cd server && mix format --check-formatted
cd server && mix credo --strict
```

**Step 3: Run all client checks**

```bash
cd client && npx oxlint src/
cd client && npx prettier --check "src/**/*.{ts,tsx,js,jsx,css}"
cd client && npm run build
```

**Step 4: Manual integration test with NATS**

1. Start NATS: `nats-server --jetstream`
2. Start PostgreSQL
3. `cd server && mix ecto.reset && mix phx.server`
4. `cd client && npm run dev`
5. Verify: play a multiplayer game -> check events flow through NATS -> match appears in history -> key moments detected

---

## Infrastructure Prerequisites

Before starting implementation (in addition to Auth plan prerequisites):

1. **NATS Server** with JetStream enabled: `nats-server --jetstream`
2. Auth & Registration plan fully implemented and merged
