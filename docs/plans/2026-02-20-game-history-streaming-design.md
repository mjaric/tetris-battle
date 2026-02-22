# Game History & Event Streaming — Design Document

Date: 2026-02-20

## Summary

Match history via event sourcing. NATS JetStream is the event store and
source of truth for all game events. Consumers project read models
(match metadata, player stats) to PostgreSQL. Key moments are detected by
heuristics and published back to the same stream. Replays are read directly
from JetStream. No separate replay or key moment tables — the stream is
the archive.

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Event store | NATS JetStream (source of truth for game events) |
| 2 | Read models | `matches` + `match_players` in Postgres (projected from events) |
| 3 | Replays | Read directly from JetStream stream |
| 4 | Key moments | Heuristic events in same stream, different subject |
| 5 | Key moment storage | Events only — no separate database table |
| 6 | Retention | 90 days on JetStream; Postgres projections are permanent |
| 7 | Solo stats | POST to REST endpoint, recorded as match in Postgres |
| 8 | LLM commentary | Deferred to future phase |
| 9 | Tournament support | Future — `tournament_id` on matches, materialized views |

---

## Section 1: Database Schema

```sql
matches (
  id            uuid PRIMARY KEY,
  game_type     text NOT NULL DEFAULT 'tetris',
  room_id       text,
  mode          text NOT NULL,   -- "multiplayer", "solo"
  player_count  integer,
  started_at    utc_datetime,
  ended_at      utc_datetime,
  inserted_at   utc_datetime
)

match_players (
  id              uuid PRIMARY KEY,
  match_id        uuid REFERENCES matches,
  user_id         uuid REFERENCES users,
  placement       integer,
  score           integer,
  lines_cleared   integer,
  garbage_sent    integer,
  garbage_received integer,
  pieces_placed   integer,
  duration_ms     integer,
  inserted_at     utc_datetime
)
```

- No `replay_events` table. 
- No `key_moments` table.
- JetStream is the event store.

### Design notes

- `matches` and `match_players` are read-model projections — derived from
  game events by the Match Projector consumer.
- Projections are permanent. Match metadata and player stats survive
  JetStream retention expiry.
- Solo mode matches have `mode: "solo"` and a single `match_players` row.
- Future: add `tournament_id` column to `matches` for tournament support.
  Tournament standings become a materialized view over `match_players`
  filtered by tournament.

---

## Section 2: NATS JetStream Architecture

```
GameRoom tick loop
    | publish
    v
Stream: GAME_EVENTS (subjects: game.>)
    |
    +---> game.{room_id}.events    (game events)
    +---> game.{room_id}.moments   (key moments)
    |
    | consumers
    v
+---------------------+    +--------------------------+
| Match Projector     |    | Key Moment Detector      |
| - Listens:          |    | - Listens:               |
|   game.*.events     |    |   game.*.events          |
| - On game_end:      |    | - Detects moments via    |
|   write match +     |    |   heuristics             |
|   player stats to   |    | - Publishes to           |
|   Postgres          |    |   game.{room_id}.moments |
+---------------------+    +--------------------------+
```

### Stream configuration

- **Stream name:** `GAME_EVENTS`
- **Subjects:** `game.>`
- **Retention:** `limits`-based (not `interest`)
- **Max age:** 90 days
- **Storage:** file

### Replay

To replay a game, consume `game.{room_id}.>` from sequence 0. This returns
all game events and key moments in order.

### Tournament support (future)

Each game keeps its own subject (`game.{room_id}`). Tournament games include
`tournament_id` in event payload. The Match Projector writes the
`tournament_id` to the `matches` table. Tournament standings are a Postgres
materialized view aggregating `match_players` by tournament. No changes to
the JetStream subject hierarchy needed.

---

## Section 3: Event Types

### Game events (published to `game.{room_id}.events`)

| Event | Data |
|-------|------|
| `game_start` | player list, room config |
| `piece_spawn` | piece type, position |
| `piece_lock` | final position, board state |
| `line_clear` | rows cleared, count |
| `garbage_sent` | target player, row count |
| `garbage_received` | from player, row count |
| `input` | action (move, rotate, drop) |
| `elimination` | player eliminated |
| `game_end` | final placements, scores, stats per player |

`game_end` includes final placements, scores, lines cleared, garbage
sent/received, pieces placed, and duration for each player. The Match
Projector uses this event to write projections.

### Key moment events (published to `game.{room_id}.moments`)

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

### Event format

Every event follows the same shape:

```
%{
  tick: integer,
  type: string,
  player_id: string,
  data: map
}
```

---

## Section 4: Server Module Architecture

```
lib/
├── platform/
│   ├── history/
│   │   ├── match.ex              # Ecto schema
│   │   └── match_player.ex       # Ecto schema
│   ├── history.ex                # Context: query matches, list history
│   ├── streaming/
│   │   ├── nats_connection.ex    # Connection supervisor
│   │   ├── stream_setup.ex       # Create JetStream stream on startup
│   │   ├── event_publisher.ex    # Publish game events to JetStream
│   │   ├── match_projector.ex    # Consumer: project game_end to Postgres
│   │   └── key_moment_detector.ex # Consumer: detect + publish moments
├── platform_web/
│   └── controllers/
│       └── solo_result_controller.ex  # POST /api/solo_results
└── tetris_game/
    └── game_room.ex              # Modified: publish events to NATS
```

### Match Projector (`Platform.Streaming.MatchProjector`)

Durable JetStream consumer subscribed to `game.*.events`. On receiving a
`game_end` event:

1. Creates a `matches` row with game metadata
2. Creates `match_players` rows with each player's final stats
3. Acknowledges the message

Idempotent — uses `room_id` + `started_at` as a natural dedup key.

### Key Moment Detector (`Platform.Streaming.KeyMomentDetector`)

Durable JetStream consumer subscribed to `game.*.events`. Maintains
per-game state (board heights, recent clears, scores) to detect moments.
When a moment is detected, publishes to `game.{room_id}.moments`.

The detector subscribes only to `.events` subjects — it never reads its
own `.moments` output (no infinite loop).

Exposes `detect_moments/2` as a public function for unit testing with
crafted event sequences.

### Event Publisher (`Platform.Streaming.EventPublisher`)

Lightweight module called from `GameRoom` tick loop. Publishes events to
`game.{room_id}.events`. Returns `:ok` silently when NATS is disabled
(test environment).

### Solo Results Endpoint

`POST /api/solo_results` — extracts Bearer JWT from Authorization header,
verifies via `Platform.Auth.Token`, finds user, records match with
`mode: "solo"`. No NATS events for solo games (they run client-side).

### History Context (`Platform.History`)

Query functions over the Postgres read models:

- `list_matches(user_id, opts)` — paginated, filterable by mode, date range
- `get_match(match_id)` — single match with player stats

### Integration with existing code

`GameRoom` is modified to call `EventPublisher.publish/2` during the tick
loop. On game start, publishes `game_start`. During ticks, publishes
per-player events. On game end, publishes `game_end` with final stats.
The publish call is fire-and-forget — NATS failure does not affect gameplay.

---

## Section 5: Client Architecture

```
src/
├── platform/
│   └── history/
│       ├── useHistory.ts         # Hook: fetch match history from server
│       └── MatchHistory.tsx      # Paginated match list
├── components/
│   └── SoloGame.tsx              # Modified: POST results when authenticated
```

### useHistory hook

Fetches match history via a channel message (`list_matches`) or REST
endpoint. Returns paginated list of matches with player stats.

### SoloGame integration

On game over, if the user is authenticated, POSTs results to
`/api/solo_results` with score, lines cleared, level reached, pieces
placed, and duration.

---

## Section 6: Error Handling

- NATS connection failure → events not published, game continues
  unaffected. Reconnect with backoff. Log warning.
- Match projection failure → log error, NATS will redeliver (durable
  consumer). Game not affected.
- Solo result with invalid/expired token → 401 Unauthorized.
- JetStream full (storage limit) → oldest messages aged out per retention
  policy. Projections in Postgres already captured the data.

---

## Section 7: Testing Strategy

- **History context:** Ecto sandbox tests for recording and querying
  matches.
- **Event publisher:** Unit tests verifying `:ok` when NATS disabled.
  Integration tests with NATS for publish/subscribe.
- **Match projector:** Unit tests with crafted `game_end` events,
  verifying correct Postgres writes.
- **Key moment detector:** Unit tests for each heuristic with crafted
  event sequences. Test that moments are published to the correct subject.
- **Solo results controller:** Controller tests with valid/invalid JWTs.
- **Client:** Mock the history hook, verify MatchHistory rendering.

---

## Dependencies

### Server (new)

- `gnat` — NATS client for JetStream

### Infrastructure

- NATS Server with JetStream enabled (`nats-server --jetstream`)

---

## Depends On

Auth & Registration — needs user IDs, Ecto repo, JWT verification for
solo endpoint.

## Independent Of

Social & Friends — can be implemented in either order.

---

## Out of Scope

- Replay viewer UI (this phase records events; viewing comes later)
- LLM commentary on key moments (future phase)
- Tournament system (future — only the `tournament_id` column is noted
  as a future addition)
- Postgres archiving of events (can be added later if replay durability
  beyond 90 days is needed)
- Spectator mode (future phase)
