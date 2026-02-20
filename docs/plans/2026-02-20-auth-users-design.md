# Auth, Users & Social — Design Document

Date: 2026-02-20

## Summary

Add authentication, user accounts, friends system, game history with replay recording, and NATS JetStream event streaming with heuristic key moment detection to the existing tetris-battle app. Firebase Auth handles identity (Google, GitHub, Discord providers + anonymous guests). PostgreSQL via Ecto stores user data. All new code lives under `Platform.*` namespace alongside existing modules.

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Auth provider | Firebase Auth (Google, GitHub, Discord + anonymous) |
| 2 | Auth flow | Firebase ID token verification on Phoenix (JWKS cached) |
| 3 | Guest play | Firebase anonymous auth, upgradeable to full account |
| 4 | Data store | PostgreSQL via Ecto (Firebase handles auth only) |
| 5 | Integration approach | Namespace separation — `Platform.*` modules in existing app |
| 6 | Friends system | Add/remove/block + online status + game invites |
| 7 | Game history | Outcome + stats + replay events (2-year retention on replays) |
| 8 | Solo mode | Auth optional; stats tracked if logged in |
| 9 | Event streaming | NATS JetStream for live game events |
| 10 | Replay storage | NATS as event bus, Postgres for long-term archive |
| 11 | Key moments | Heuristic detection only (no LLM commentary in this phase) |
| 12 | LLM commentary | Deferred to a future phase |

---

## Section 1: Authentication Flow

### Client-side (React)

- Firebase JS SDK handles all auth UI and provider flows (Google, GitHub, Discord)
- New users land on a login/register screen. Anonymous auth creates a temporary identity for guests.
- After Firebase auth, the client gets an ID token and passes it as a `token` param on WebSocket connect
- On anonymous-to-full-account upgrade, Firebase links the accounts; the server updates the user record

### Server-side (Phoenix)

- `Platform.Auth.FirebaseToken` module verifies Firebase JWT ID tokens:
  - Fetches and caches Google's JWKS public keys (refresh on `Cache-Control` expiry or unknown `kid`)
  - Validates signature (RS256), expiry, issuer, audience
  - Extracts `sub` (Firebase UID), `email`, provider info
- `UserSocket.connect/3` calls `FirebaseToken.verify/1` — rejects connection if invalid
- On first valid connection for a new Firebase UID, creates a `Platform.Accounts.User` record in Postgres
- Anonymous users get a user record with `is_anonymous: true`; on upgrade, record is merged

### Token refresh

- Firebase ID tokens expire after 1 hour. The client refreshes via Firebase SDK and reconnects the socket with the new token.
- Phoenix channels survive brief disconnects via rejoin logic already in the Phoenix JS client.

---

## Section 2: Database Schema

```sql
-- Core identity
users (
  id            uuid PRIMARY KEY,
  firebase_uid  text UNIQUE NOT NULL,
  email         text,
  display_name  text NOT NULL,
  avatar_url    text,
  provider      text,          -- "google", "github", "discord", "anonymous"
  is_anonymous  boolean DEFAULT false,
  settings      jsonb DEFAULT '{}',  -- preferences (theme, controls, sound)
  inserted_at   utc_datetime,
  updated_at    utc_datetime
)

-- Friends
friendships (
  id          uuid PRIMARY KEY,
  user_id     uuid REFERENCES users,
  friend_id   uuid REFERENCES users,
  status      text NOT NULL,   -- "pending", "accepted", "blocked"
  inserted_at utc_datetime,
  UNIQUE(user_id, friend_id)
)

-- Match records
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

-- Per-player match results
match_players (
  id              uuid PRIMARY KEY,
  match_id        uuid REFERENCES matches,
  user_id         uuid REFERENCES users,
  placement       integer,         -- 1st, 2nd, 3rd...
  score           integer,
  lines_cleared   integer,
  garbage_sent    integer,
  garbage_received integer,
  pieces_placed   integer,
  duration_ms     integer,         -- how long this player survived
  inserted_at     utc_datetime
)

-- Replay event logs (retention: 2 years)
replay_events (
  id          uuid PRIMARY KEY,
  match_id    uuid REFERENCES matches ON DELETE CASCADE,
  event_log   bytea,             -- compressed event stream
  metadata    jsonb,             -- tick count, version, etc.
  expires_at  utc_datetime,      -- inserted_at + 2 years
  inserted_at utc_datetime
)

-- Key moments detected by heuristics
key_moments (
  id          uuid PRIMARY KEY,
  match_id    uuid REFERENCES matches ON DELETE CASCADE,
  tick        integer NOT NULL,
  player_id   text,
  event_type  text NOT NULL,     -- "tetris", "t_spin_double", "near_death_survival", etc.
  description text,              -- heuristic-generated description
  context     jsonb,             -- board height, garbage pending, score, etc.
  inserted_at utc_datetime
)
```

### Design notes

- `settings` as JSONB — flexible for preferences without schema migrations per setting
- `friendships` as a directional pair — user A sends request to user B. Query both directions for the full friends list
- `replay_events` stored as compressed binary blob per match (not per-tick rows) — efficient storage, loaded in bulk for replay viewer
- `expires_at` on replays for the 2-year retention policy; a periodic job cleans expired records
- `key_moments` links to matches and stores heuristic-detected events with game context

---

## Section 3: Server Module Architecture

New modules under the `Platform.*` namespace, alongside existing `Tetris.*`/`TetrisGame.*`/`TetrisWeb.*`:

```
lib/
├── platform/
│   ├── auth/
│   │   ├── firebase_token.ex     # JWT verification, JWKS caching
│   │   └── token_cache.ex        # GenServer for cached Firebase public keys
│   ├── accounts/
│   │   ├── user.ex               # Ecto schema
│   │   └── accounts.ex           # Context: create/get/update users, anonymous upgrade
│   ├── social/
│   │   ├── friendship.ex         # Ecto schema
│   │   └── social.ex             # Context: send/accept/block, friends list, online status
│   ├── history/
│   │   ├── match.ex              # Ecto schema
│   │   ├── match_player.ex       # Ecto schema
│   │   ├── replay_event.ex       # Ecto schema
│   │   ├── key_moment.ex         # Ecto schema
│   │   ├── history.ex            # Context: record matches, query history
│   │   └── replay_cleaner.ex     # Periodic job: delete expired replays
│   ├── streaming/
│   │   ├── nats_connection.ex    # NATS connection supervisor (Gnat library)
│   │   ├── event_publisher.ex    # Publishes game events to JetStream
│   │   ├── replay_archiver.ex    # Consumer: archives replays to Postgres
│   │   ├── key_moment_detector.ex # Consumer: detects key moments via heuristics
│   │   └── stream_setup.ex       # Creates JetStream streams/consumers on startup
│   └── repo.ex                   # Ecto.Repo
├── platform_web/
│   ├── presence.ex               # Phoenix Presence for online status
│   ├── user_socket_auth.ex       # Firebase token verification on socket connect
│   └── channels/
│       ├── social_channel.ex     # "social:{user_id}" — friend requests, invites, presence
│       └── lobby_channel_ext.ex  # Extensions to existing lobby channel (user identity)
├── tetris/         # (existing, unchanged)
├── tetris_game/    # (existing, minor changes)
│   └── game_room.ex              # Modified: publish events to NATS, record match on end
└── tetris_web/     # (existing, minor changes)
    └── user_socket.ex            # Modified: verify Firebase token on connect
```

### Integration points with existing code (minimal changes)

1. `UserSocket.connect/3` — add Firebase token verification, attach `user_id` to socket assigns
2. `GameChannel.join/3` — use `socket.assigns.user_id` instead of nickname-only identity
3. `GameRoom` — publish events to NATS during tick loop; on game end, signal consumers
4. `LobbyChannel` — include user display names and auth status in room listings

### Phoenix Presence

Used for online/in-game status tracking — built into Phoenix, no external dependency. Friends see real-time online/offline/in-game status via the social channel.

---

## Section 4: NATS JetStream Event Streaming

### Architecture

```
GameRoom tick loop
    ↓ (publish each event)
NATS JetStream subject: "game.{room_id}.events"
    ↓ (consumers)
┌───────────────────────┐    ┌──────────────────────────┐
│ Replay Archiver       │    │ Key Moment Detector      │
│ - Buffers events      │    │ - Heuristic rules        │
│ - On game end:        │    │ - Detects: Tetris,       │
│   compress + write    │    │   T-spin, near-death,    │
│   to Postgres         │    │   comeback, perfect      │
│                       │    │   clear, garbage surge   │
│                       │    │ - Writes detected events │
│                       │    │   to Postgres            │
└───────────────────────┘    └──────────────────────────┘
```

### Event publishing

- `GameRoom` publishes events to NATS during the tick loop via a lightweight async call
- Events: `piece_spawn`, `piece_lock`, `line_clear`, `garbage_sent`, `garbage_received`, `input`, `elimination`, `game_start`, `game_end`
- Each event: `%{tick: integer, type: atom, player_id: string, data: map}`
- NATS JetStream subject pattern: `game.{room_id}.events`
- JetStream retention: interest-based (retained while consumers exist), max age ~7 days as safety net

### Consumers

1. **Replay Archiver** (`Platform.Streaming.ReplayArchiver`) — durable consumer, buffers events per match, on `game_end` event compresses and writes to `replay_events` table
2. **Key Moment Detector** (`Platform.Streaming.KeyMomentDetector`) — durable consumer, applies heuristic rules to the event stream, writes detected moments to `key_moments` table

### Key moment heuristics

- 4-line clear (Tetris)
- T-spin (single, double, triple)
- Back-to-back bonus chains
- Garbage surge (3+ garbage rows sent in sequence)
- Near-death survival (board above row 16, then cleared below row 10)
- Elimination moment
- Comeback (last place to winning)
- Perfect clear (board empty after line clear)

### Dependency

`gnat` — Elixir NATS client library

---

## Section 5: Client Architecture

### New React structure

```
src/
├── platform/
│   ├── auth/
│   │   ├── FirebaseProvider.tsx    # Firebase app init + auth context
│   │   ├── AuthGuard.tsx          # Route protection (redirect to login if needed)
│   │   ├── LoginScreen.tsx        # Sign in with Google/GitHub/Discord + guest play
│   │   └── useAuth.ts             # Hook: current user, sign in/out, token refresh
│   ├── profile/
│   │   ├── ProfilePage.tsx        # User profile with stats, match history
│   │   ├── SettingsPage.tsx       # User preferences (theme, controls, sound)
│   │   └── useProfile.ts          # Hook: profile data, settings updates
│   ├── social/
│   │   ├── FriendsList.tsx        # Friends panel (sidebar or overlay)
│   │   ├── FriendRequest.tsx      # Incoming/outgoing request management
│   │   ├── GameInvite.tsx         # Invite notification + accept/decline
│   │   └── useSocial.ts           # Hook: friends channel, presence, invites
│   └── history/
│       ├── MatchHistory.tsx       # Match list with filters
│       └── useHistory.ts          # Hook: fetch match history
├── components/     # (existing, minor changes)
│   ├── App.tsx                    # Modified: wrap with FirebaseProvider, add auth routes
│   ├── MainMenu.tsx               # Modified: show user info, logout option
│   └── Lobby.tsx                  # Modified: show friend invites, user identities
├── hooks/          # (existing, minor changes)
│   └── useSocket.ts               # Modified: pass Firebase ID token on connect
└── ...
```

### App flow changes

- `App.tsx` wraps everything in `FirebaseProvider`
- New screen states: `login → menu → ...` (existing flow continues after menu)
- `useSocket` modified to include the Firebase ID token in socket params
- `MainMenu` shows user avatar/name, logout button, links to profile/friends
- `Lobby` shows friend online indicators, invite buttons next to friend names
- Guest users see a "Sign in for full features" prompt but can play immediately

### Firebase config

- Firebase project config stored in environment variables (Vite `VITE_FIREBASE_*`)
- Firebase JS SDK initialized in `FirebaseProvider`

---

## Section 6: Friends System & Game Invites

### Social Channel

Each authenticated user joins `social:{user_id}` on connect. This channel handles:

- **Presence:** Phoenix Presence tracks who's online and their current status (`online`, `in_game:{room_id}`, `in_lobby`)
- **Friend requests:** `send_friend_request`, `accept_friend_request`, `decline_friend_request`, `block_user`
- **Game invites:** `send_game_invite` (includes room_id), `accept_invite`, `decline_invite`

### Friend request flow

1. User A searches for User B by display name (or from recent opponents)
2. Sends friend request → creates `friendship` row with `status: "pending"`
3. User B receives real-time notification via social channel
4. Accept → status becomes `"accepted"`, reverse friendship row created
5. Both users now see each other in friends list with online status

### Game invite flow

1. User A is in a game room (or lobby)
2. Opens friends panel, clicks "Invite" next to an online friend
3. Server pushes invite to User B's social channel
4. User B sees a toast/notification with accept/decline
5. Accept → client auto-joins the room via the existing lobby join flow

### Finding friends

- Search by display name (fuzzy match)
- "Recent opponents" list from match history

---

## Section 7: Game History & Replay Recording

### Recording matches

- When `GameRoom` detects a game has ended, the replay archiver consumer (subscribed to NATS) compresses the buffered events and writes to Postgres
- The key moment detector consumer writes detected moments to the `key_moments` table
- Both consumers operate asynchronously from the game loop

### Event log format

- Events published to NATS during gameplay: `piece_spawn`, `piece_lock`, `line_clear`, etc.
- Each event: `%{tick: integer, type: atom, player_id: string, data: map}`
- On game end, the replay archiver compresses the full event sequence (`:zlib.gzip/1`) and stores as `bytea` in `replay_events`

### Solo mode recording (when authenticated)

- Client-side solo mode reports results to a new REST endpoint (`POST /api/solo_results`) after game over
- Sends: score, lines cleared, level reached, pieces placed, duration
- No replay events for solo (runs client-side, no event stream available)
- Server validates the token and records a `match` with `mode: "solo"`

### Replay retention

- `replay_events.expires_at` set to `inserted_at + 2 years`
- `Platform.History.ReplayCleaner` — a periodic GenServer (runs daily via `Process.send_after`) that deletes expired replay records
- Match metadata and player stats are retained permanently (only replay event blobs expire)

### Querying history

- `Platform.History.list_matches(user_id, opts)` — paginated, filterable by game type, mode, date range
- `Platform.History.get_match_with_replay(match_id)` — full match data including decompressed event log

---

## Section 8: Error Handling & Testing

### Error handling

- Invalid/expired Firebase token on socket connect → connection rejected, client redirects to login
- Firebase JWKS fetch failure → serve from cache (stale keys still valid for hours); log warning
- Anonymous-to-full upgrade conflict (email already exists) → merge accounts, keep the one with more history
- Friend request to self / duplicate request → return error tuple, client shows appropriate message
- Match recording failure → log error, don't crash game room (fire-and-forget with error logging)
- NATS connection failure → events not published, game continues unaffected; reconnect with backoff

### Testing strategy

- **Pure modules** (`Platform.Auth.FirebaseToken`, `Platform.Accounts`, `Platform.Social`, `Platform.History`): standard ExUnit tests with Ecto sandbox
- **Firebase token verification**: test with pre-generated JWTs signed by a test RSA key; mock JWKS endpoint in test config
- **Channel tests**: existing test patterns extended for social channel
- **NATS streaming**: test with embedded NATS server or mock the `Gnat` client in tests
- **Key moment detection**: unit tests with crafted event sequences that trigger each heuristic
- **Client tests**: React Testing Library for auth flows, mock Firebase SDK, mock Phoenix socket
- **Integration**: end-to-end flow tests covering login → join lobby → play game → check match history

---

## Dependencies

### Server (new)

- `ecto` + `ecto_sql` + `postgrex` — PostgreSQL integration
- `gnat` — NATS client for JetStream
- `jose` — JWT verification (Firebase ID tokens)

### Client (new)

- `firebase` — Firebase JS SDK (auth module)

---

## Out of Scope

- LLM commentary (future phase)
- Platform plugin/microservice architecture (separate design session)
- Replay viewer UI (future — this phase records replays, viewing comes later)
- Ranked matchmaking / ELO (P2)
- Spectator mode (P3)
