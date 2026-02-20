# Game History & Event Streaming — Implementation Plan (Plan 2 of 2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add match history with replay recording, NATS JetStream event streaming, heuristic key moment detection, solo stats reporting, and match history UI.

**Architecture:** Game events published to NATS JetStream during tick loop. Two consumers: replay archiver (compresses and stores in Postgres) and key moment detector (detects moments, publishes back as events to NATS, included in archived replay). PostgreSQL stores match metadata, per-player stats, and compressed replay blobs.

**Tech Stack:** Gnat (NATS client), Ecto (existing from Plan 1), zlib (compression)

**Design doc:** `docs/plans/2026-02-20-auth-users-design.md`

**Depends on:** Plan 1 (Auth, Users & Social) — needs user IDs, Ecto repo, Firebase auth

---

## Task 1: Match History Schema and Context

**Files:**
- Create: `server/priv/repo/migrations/*_create_matches.exs`
- Create: `server/lib/platform/history/match.ex`
- Create: `server/lib/platform/history/match_player.ex`
- Create: `server/lib/platform/history/replay_event.ex`
- Create: `server/lib/platform/history.ex`
- Create: `server/lib/platform/history/replay_cleaner.ex`
- Create: `server/test/platform/history_test.exs`
- Modify: `server/lib/tetris/application.ex`

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

    create table(:replay_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :match_id, references(:matches, type: :binary_id, on_delete: :delete_all), null: false
      add :event_log, :binary
      add :metadata, :map, default: %{}
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:replay_events, [:match_id])
    create index(:replay_events, [:expires_at])
  end
end
```

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
    has_one :replay_event, Platform.History.ReplayEvent

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

Create `server/lib/platform/history/replay_event.ex`:

```elixir
defmodule Platform.History.ReplayEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @retention_years 2

  schema "replay_events" do
    belongs_to :match, Platform.History.Match

    field :event_log, :binary
    field :metadata, :map, default: %{}
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(replay, attrs) do
    replay
    |> cast(attrs, [:match_id, :event_log, :metadata, :expires_at])
    |> validate_required([:match_id, :event_log])
    |> set_default_expiry()
  end

  defp set_default_expiry(changeset) do
    if get_field(changeset, :expires_at) do
      changeset
    else
      expiry = DateTime.utc_now() |> DateTime.add(@retention_years * 365 * 24 * 3600)
      put_change(changeset, :expires_at, DateTime.truncate(expiry, :second))
    end
  end
end
```

**Step 3: Write History context**

Create `server/lib/platform/history.ex`:

```elixir
defmodule Platform.History do
  import Ecto.Query
  alias Platform.Repo
  alias Platform.History.{Match, MatchPlayer, ReplayEvent}

  def record_match(attrs) do
    Repo.transaction(fn ->
      {:ok, match} =
        %Match{}
        |> Match.changeset(Map.drop(attrs, [:players, :event_log, :replay_metadata]))
        |> Repo.insert()

      if attrs[:players] do
        Enum.each(attrs.players, fn player_attrs ->
          {:ok, _} =
            %MatchPlayer{}
            |> MatchPlayer.changeset(Map.put(player_attrs, :match_id, match.id))
            |> Repo.insert()
        end)
      end

      if attrs[:event_log] do
        compressed = :zlib.gzip(attrs.event_log)

        {:ok, _} =
          %ReplayEvent{}
          |> ReplayEvent.changeset(%{
            match_id: match.id,
            event_log: compressed,
            metadata: attrs[:replay_metadata] || %{}
          })
          |> Repo.insert()
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

  def get_match_with_replay(match_id) do
    match =
      Match
      |> Repo.get(match_id)
      |> Repo.preload([:match_players, :replay_event])

    case match do
      nil ->
        {:error, :not_found}

      %{replay_event: %ReplayEvent{event_log: compressed}} = match ->
        decompressed = :zlib.gunzip(compressed)
        {:ok, match, decompressed}

      match ->
        {:ok, match, nil}
    end
  end

  def delete_expired_replays do
    now = DateTime.utc_now()

    {count, _} =
      from(r in ReplayEvent, where: r.expires_at <= ^now)
      |> Repo.delete_all()

    {:ok, count}
  end
end
```

**Step 4: Write ReplayCleaner**

Create `server/lib/platform/history/replay_cleaner.ex`:

```elixir
defmodule Platform.History.ReplayCleaner do
  use GenServer

  @clean_interval :timer.hours(24)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_clean()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:clean, state) do
    {:ok, count} = Platform.History.delete_expired_replays()

    if count > 0 do
      require Logger
      Logger.info("ReplayCleaner: deleted #{count} expired replay(s)")
    end

    schedule_clean()
    {:noreply, state}
  end

  defp schedule_clean do
    Process.send_after(self(), :clean, @clean_interval)
  end
end
```

Add to supervision tree in `server/lib/tetris/application.ex`:

```elixir
Platform.History.ReplayCleaner,
```

**Step 5: Write tests**

Create `server/test/platform/history_test.exs`:

```elixir
defmodule Platform.HistoryTest do
  use ExUnit.Case, async: true

  alias Platform.Accounts
  alias Platform.History

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Platform.Repo)

    {:ok, alice} = Accounts.create_user(%{firebase_uid: "hist_alice", display_name: "Alice"})
    {:ok, bob} = Accounts.create_user(%{firebase_uid: "hist_bob", display_name: "Bob"})

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
    end

    test "records a match with replay events", %{alice: alice} do
      event_log = Jason.encode!([%{tick: 1, type: "piece_spawn", data: %{}}])

      attrs = %{
        mode: "multiplayer",
        player_count: 1,
        players: [%{user_id: alice.id, placement: 1, score: 1000}],
        event_log: event_log
      }

      assert {:ok, match} = History.record_match(attrs)
      assert {:ok, _match, decompressed} = History.get_match_with_replay(match.id)
      assert decompressed == event_log
    end
  end

  describe "list_matches/2" do
    test "returns matches for a user", %{alice: alice} do
      History.record_match(%{
        mode: "solo",
        players: [%{user_id: alice.id, score: 1000}]
      })

      matches = History.list_matches(alice.id)
      assert length(matches) == 1
    end
  end

  describe "delete_expired_replays/0" do
    test "deletes expired replays", %{alice: alice} do
      {:ok, match} =
        History.record_match(%{
          mode: "solo",
          players: [%{user_id: alice.id, score: 100}],
          event_log: "test data"
        })

      replay = Platform.Repo.get_by(Platform.History.ReplayEvent, match_id: match.id)

      replay
      |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.add(-1))
      |> Platform.Repo.update!()

      assert {:ok, 1} = History.delete_expired_replays()
    end
  end
end
```

**Step 6: Run migration and tests**

```bash
cd server && mix ecto.migrate
cd server && mix test test/platform/history_test.exs -v
cd server && mix test
```

**Step 7: Commit**

```bash
git add server/priv/repo/migrations/ server/lib/platform/history/ \
  server/lib/platform/history.ex server/lib/tetris/application.ex \
  server/test/platform/history_test.exs
git commit -m "feat: add match history, replay storage, and replay cleaner"
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
      retention: :interest,
      max_age: 7 * 24 * 60 * 60 * 1_000_000_000,
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

**Step 5: Add to supervision tree**

In `server/lib/tetris/application.ex`, add:

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

1. After `broadcast_state` in `process_tick`, add call to `publish_events_to_nats(state)`
2. In the `start_game` handler, publish a `game_start` event
3. Add helper function:

```elixir
defp publish_events_to_nats(state) do
  events =
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

  lifecycle_events =
    if state.status == :finished do
      [%{tick: state.tick, type: "game_end", data: %{eliminated_order: state.eliminated_order}}]
    else
      []
    end

  all_events = events ++ lifecycle_events

  if all_events != [] do
    Platform.Streaming.EventPublisher.publish_batch(state.room_id, all_events)
  end
end
```

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

## Task 4: Replay Archiver and Key Moment Detector Consumers

**Files:**
- Create: `server/lib/platform/streaming/replay_archiver.ex`
- Create: `server/lib/platform/streaming/key_moment_detector.ex`
- Create: `server/test/platform/streaming/key_moment_detector_test.exs`
- Modify: `server/lib/tetris/application.ex`

**Step 1: Write ReplayArchiver consumer**

Create `server/lib/platform/streaming/replay_archiver.ex` — NATS consumer that buffers events per room, compresses and archives to Postgres on `game_end`. Returns `:ignore` when NATS disabled.

**Step 2: Write KeyMomentDetector consumer**

Create `server/lib/platform/streaming/key_moment_detector.ex` — NATS consumer that detects key moments (Tetris, b2b, garbage surge, elimination, near-death survival, comeback, perfect clear) and publishes them back to `game.{room_id}.moments`. Key moments are events, not stored in a separate table. The replay archiver can optionally subscribe to moments too to include them in the archive.

Expose `detect_moments/2` as a public function for unit testing.

**Step 3: Write tests for key moment detection**

Create `server/test/platform/streaming/key_moment_detector_test.exs` — unit tests for each heuristic with crafted event inputs.

**Step 4: Add consumers to supervision tree**

```elixir
Platform.Streaming.ReplayArchiver,
Platform.Streaming.KeyMomentDetector,
```

**Step 5: Run tests**

```bash
cd server && mix test
```

**Step 6: Commit**

```bash
git add server/lib/platform/streaming/ server/lib/tetris/application.ex \
  server/test/platform/streaming/
git commit -m "feat: add replay archiver and key moment detector NATS consumers"
```

---

## Task 5: Solo Results REST Endpoint

**Files:**
- Create: `server/lib/platform_web/controllers/solo_result_controller.ex`
- Create: `server/lib/platform_web/router.ex`
- Modify: `server/lib/tetris_web/endpoint.ex`

**Step 1: Create Platform router with `/api/solo_results` POST endpoint**

**Step 2: Create SoloResultController**

Extracts Bearer token from Authorization header, verifies via FirebaseToken, finds/creates user, records match with `mode: "solo"`.

**Step 3: Mount platform router in endpoint**

**Step 4: Run tests**

```bash
cd server && mix test
```

**Step 5: Commit**

```bash
git add server/lib/platform_web/
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

Fetches match history via social channel message (`list_matches`) or a dedicated history channel.

**Step 2: Create MatchHistory component**

Paginated match list with date, mode, placement, score, lines.

**Step 3: Modify SoloGame to report results**

On game over, if authenticated, POST to `/api/solo_results` with score, lines, pieces, duration.

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

**Step 2: Run all client checks**

```bash
cd client && npx oxlint src/
cd client && npx prettier --check "src/**/*.{ts,tsx,js,jsx,css}"
cd client && npm run build
```

**Step 3: Manual integration test with NATS**

1. Start NATS: `nats-server --jetstream`
2. Start PostgreSQL
3. `cd server && mix ecto.reset && mix phx.server`
4. `cd client && npm run dev`
5. Verify: play a multiplayer game -> check events flow through NATS -> match appears in history -> key moments detected

---

## Infrastructure Prerequisites

Before starting implementation (in addition to Plan 1 prerequisites):

1. **NATS Server** with JetStream enabled: `nats-server --jetstream`
2. Plan 1 fully implemented and merged
