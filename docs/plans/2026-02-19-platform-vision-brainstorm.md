# Platform Vision & Roadmap — Brainstorming Session

Date: 2026-02-19

## Executive Summary

Evolve the current multiplayer Tetris battle game into a **competitive gaming platform** — a shell with game-plugin architecture where Tetris is the first game, and third-party developers can build and publish additional games via an SDK. The platform delivers ranked matchmaking, tournaments, spectating, replays, AI bots with genetically-evolved strategies, and LLM-powered analytical commentary.

This document captures all decisions from the initial brainstorming session across 9 development phases.

---

## Product Vision

**What we're building:** A competitive gaming platform, not just a Tetris game.

**Core thesis:** Build the platform infrastructure (accounts, matchmaking, rankings, spectating, tournaments, replays) around Tetris as the flagship game, then open an SDK so other developers create games while we build the player marketplace.

**Monetization:** Identified as important but deferred — not in scope for initial phases.

---

## Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target platform | Web-first, responsive for mobile | Broadest reach, existing React stack |
| Deployment | Fly.io with Erlang clustering | Native BEAM clustering, global edge deployment |
| Database | PostgreSQL | Mature, great Ecto support, handles relational data well |
| Authentication | OAuth (Google/GitHub/Discord) + guest play | Low friction entry, social login for retention |
| Solo mode | Keep client-side for now, migrate to server later | Working code, no urgency to rewrite |
| Matchmaking | ELO-based with skill tiers | Industry standard for competitive games |
| Bot difficulty | Continuous slider (not discrete levels) | More granular challenge, better matchmaking against humans |
| Architecture | Shell + game plugin from P1 | SDK-first design enables third-party game ecosystem |
| Replay storage | Server-side with retention policy | Tournament replays permanent, casual replays expire |
| Analytics engine | Heuristics detect events, LLM narrates | Best of both: reliable detection + engaging commentary |
| Bot workers | In-process Phoenix workers, scales with cluster | Simplicity, scales horizontally with Fly.io clustering |
| Verify-task scope | Tests + compilation + linter + format + acceptance criteria | Comprehensive quality gate |

---

## Phase Breakdown

### P1 — Platform Shell & Game Plugin Architecture

**Goal:** Restructure the codebase from a monolithic Tetris app into a platform shell that hosts game plugins. Tetris becomes the first plugin.

**Architecture:**

```
platform-shell/
├── shell/                    # Platform core (accounts, lobby, matchmaking framework)
│   ├── lib/
│   │   ├── platform/         # Core platform logic
│   │   │   ├── accounts/     # User management, OAuth, profiles
│   │   │   ├── matchmaking/  # Generic matchmaking framework
│   │   │   ├── lobby/        # Platform-level lobby
│   │   │   └── game_sdk/     # Plugin interface definitions (behaviours)
│   │   ├── platform_web/     # Phoenix web layer
│   │   └── platform_game/    # Game process supervision
│   └── mix.exs
├── games/
│   └── tetris/               # First game plugin
│       ├── lib/tetris/       # All current game logic
│       └── mix.exs           # Depends on platform SDK
├── client/                   # React frontend
│   ├── src/
│   │   ├── platform/         # Shell UI (auth, lobby, profile)
│   │   └── games/
│   │       └── tetris/       # Tetris-specific UI
│   └── package.json
└── sdk/                      # Published SDK for third-party devs
    └── lib/game_sdk/         # Behaviours, helpers, test harness
```

**Game Plugin Interface (Elixir Behaviours):**

```elixir
defmodule Platform.GameSDK.GameBehaviour do
  @callback init(config :: map()) :: {:ok, state :: term()}
  @callback handle_input(player_id, action, state) :: {:ok, state}
  @callback tick(state) :: {:ok, state}
  @callback get_broadcast_state(state) :: map()
  @callback max_players() :: pos_integer()
  @callback min_players() :: pos_integer()
end
```

**Key deliverables:**
- Platform shell with generic lobby, room creation, game lifecycle management
- Game SDK behaviour definitions
- Tetris refactored as first game plugin implementing the SDK
- OAuth integration (Google, GitHub, Discord) + guest play
- PostgreSQL setup via Ecto for accounts, profiles, game history
- Platform-level UI shell (auth screens, game selector, profile)

**Database schema (initial):**

```
users (id, email, display_name, avatar_url, provider, provider_id, inserted_at)
sessions (id, user_id, token, expires_at)
game_types (id, name, slug, version, config_schema)
```

---

### P2 — Ranked Matchmaking & ELO System

**Goal:** Competitive ranked play with skill-based matchmaking and visible progression.

**ELO system:**
- Standard ELO with K-factor adjustments (higher K for new players, lower for established)
- Per-game-type ratings (Tetris ELO separate from future games)
- Skill tiers with named ranks (e.g., Bronze → Silver → Gold → Platinum → Diamond → Master → Grandmaster)
- Tier boundaries based on ELO ranges
- Placement matches for new players (10 games, higher K-factor)

**Matchmaking algorithm:**
- Queue-based: players enter queue, system finds matches within ELO range
- ELO window expands over wait time (start ±50, expand to ±200 after 30s)
- Party queue support (average party ELO for matching)
- Separate queues: casual (no ELO change) and ranked

**Database schema additions:**

```
player_ratings (id, user_id, game_type_id, elo, tier, games_played, wins, losses)
match_history (id, game_type_id, room_id, started_at, ended_at, player_count)
match_players (id, match_id, user_id, placement, elo_before, elo_change, stats_json)
```

**Key deliverables:**
- ELO calculation module (pure logic, no side effects)
- Matchmaking GenServer with expanding window algorithm
- Ranked queue UI with estimated wait time
- Post-game ELO change display (+/- animation)
- Player profile page with rating history graph
- Leaderboard (global + per-tier)
- Season system foundation (reset schedule, rewards tracking)

---

### P3 — Spectator Mode

**Goal:** Allow anyone to watch live games in real-time.

**Architecture:**
- Spectators join the same Phoenix Channel as players (`game:{room_id}`) but with a `spectator` role
- Receive the same `game_state` broadcasts — zero additional server cost per spectator
- No input handling for spectators (read-only channel membership)
- Spectator count displayed in lobby and in-game

**Features:**
- Watch any in-progress game from lobby
- Spectator-specific UI: can view any player's board full-size (click to focus)
- Live spectator count badge
- Optional 3-second delay for ranked games (anti-ghosting)
- Streamlined spectate URL (shareable link: `/watch/{room_id}`)

**Key deliverables:**
- Channel role system (player vs spectator)
- Spectator join/leave flow in lobby UI
- Multi-board spectator view with player focus selection
- Spectator count in game state broadcast
- Anti-ghosting delay for ranked matches

---

### P4 — Bot System — Continuous Difficulty & Human-Like Metrics

**Goal:** Transform the discrete bot difficulty levels into a continuous difficulty slider. Track comprehensive performance metrics for both bots and humans.

**Continuous difficulty slider:**
- Single slider from 0.0 (easiest) to 1.0 (hardest)
- Interpolates between weight sets: easy(0.0) → medium(0.33) → hard(0.66) → battle(1.0)
- Weight interpolation: `w = w_low * (1-t) + w_high * t` where `t` is position within segment
- Think time also scales: 500ms at 0.0 → 50ms at 1.0
- Action delay scales: 200ms at 0.0 → 30ms at 1.0
- Lookahead: none below 0.33, greedy 0.33-0.66, pruned 2-piece above 0.66

**Metrics tracking (same for bots AND humans):**

Solo metrics (8):
| Metric | Description |
|--------|-------------|
| Aggregate height | Sum of all column heights |
| Holes | Empty cells with filled cells above |
| Bumpiness | Surface unevenness |
| Lines cleared | Total lines cleared |
| Max height | Tallest column |
| Well sum | Deep well penalty |
| Row transitions | Horizontal fill-state changes |
| Column transitions | Vertical fill-state changes |

Battle metrics (6 additional):
| Metric | Description |
|--------|-------------|
| Garbage pressure | Penalty for pending garbage × board height |
| Attack bonus | Reward for sending garbage |
| Danger aggression | Line clears when opponents are near death |
| Survival height | Conservative play as board fills |
| Tetris bonus | 4-line clear frequency |
| Line efficiency | Multi-line clear ratio |

Plus:
| Metric | Description |
|--------|-------------|
| Generation | GA generation number (bots) or "human" marker |
| Pieces per second | Input speed |
| T-spin rate | T-spin frequency per game |
| Downstack speed | Lines cleared per second when board is above height 12 |

**Database schema additions:**

```
player_metrics (id, user_id, game_type_id, match_id, metrics_json, recorded_at)
bot_configurations (id, difficulty_value, weight_snapshot_json, generation, fitness)
```

**Key deliverables:**
- Continuous difficulty slider with weight interpolation
- Unified metrics computation module (works for both human and bot play)
- Per-game metrics recording to database
- Player stats dashboard (personal metrics over time)
- Bot vs human metrics comparison view
- Difficulty recommendation based on player's recent performance

---

### P5 — Chain System (Multi-Generation Bot Evolution)

**Goal:** Evolve bots across multiple generations where each generation builds on the previous one's knowledge, creating increasingly sophisticated play styles.

**Chain concept:**
- A "chain" is a lineage of bot generations
- Generation N's best genome seeds Generation N+1's initial population
- Each generation can introduce new training conditions (e.g., different opponents, different board states)
- Chains are named and tracked (e.g., "aggressive-v3", "defensive-v2")

**Chain architecture:**

```elixir
defmodule BotTrainer.Chain do
  @type t :: %__MODULE__{
    name: String.t(),
    generations: [generation()],
    current_gen: non_neg_integer(),
    config: chain_config()
  }

  @type generation :: %{
    number: non_neg_integer(),
    best_genome: genome(),
    fitness: float(),
    training_config: map(),
    trained_at: DateTime.t()
  }
end
```

**Training pipeline:**
1. Start chain from scratch or fork from existing chain
2. Each generation runs GA evolution (solo or battle mode)
3. Best genome → seed next generation's population (elitism)
4. Training conditions can escalate:
   - Gen 1-5: solo training (learn basics)
   - Gen 6-10: battle vs static opponents (learn aggression)
   - Gen 11+: co-evolution (battle vs previous generation's best)
5. Chain metadata and all generation snapshots stored in DB

**Lineage tracking:**
- Full ancestry: which chain/generation produced each bot
- Performance regression detection: if gen N+1 is worse than gen N, flag and optionally rollback
- Branch chains: fork from any generation to explore alternative training strategies

**Database schema additions:**

```
bot_chains (id, name, description, game_type_id, created_at)
bot_generations (id, chain_id, number, genome_json, fitness, training_config_json, parent_gen_id, trained_at)
```

**Key deliverables:**
- Chain management module (create, fork, advance, rollback)
- Mix tasks: `mix bot.chain.new`, `mix bot.chain.advance`, `mix bot.chain.status`
- Generation lineage visualization (tree view in admin UI)
- Automated regression detection and alerting
- Chain comparison tools (pit different chains against each other)
- Live weight micro-adjustments: Phoenix worker processes adjust weights after each game, running in the cluster alongside game rooms (scales with Fly.io horizontal scaling)

---

### P6 — Tournament System

**Goal:** Organized competitive events with group stages, knockout brackets, and analytical commentary.

**Tournament format (48 players):**

```
Registration (48 players)
    ↓
Group Stage: 12 groups × 4 players
    → Round-robin within each group
    → Top 2 per group advance (24 players)
    ↓
Knockout Stage: Single-elimination bracket
    → Round of 24 → Round of 12 → Quarterfinals → Semifinals → Final
    ↓
Results + Replay Archive
```

**Group stage:**
- 12 groups of 4 players each
- Round-robin: every player plays every other player in their group (6 matches per group)
- Points: Win = 3pts, Draw = 1pt (if applicable), Loss = 0pts
- Tiebreaker: head-to-head → lines cleared → garbage sent
- Top 2 from each group advance to knockout (24 players)

**Knockout stage:**
- Single elimination, best-of-3 matches
- Bracket seeded by group stage performance
- Semi-finals and finals: best-of-5

**Replay system:**
- Event-log based: store sequence of game events (inputs, piece spawns, line clears, garbage)
- Stored server-side in PostgreSQL
- Retention policy:
  - Tournament replays: permanent (stored per tournament folder/namespace)
  - Casual ranked replays: expire after 30 days
  - Unranked replays: not stored
- Replay viewer: step-through, speed control (0.5x, 1x, 2x, 4x), jump to key moments
- Shareable replay links

**Analytical engine (key moments detection):**

Layer 1 — Heuristic event detection:
- 4-line clear (Tetris)
- T-spin (single, double, triple)
- Back-to-back bonus chains
- Garbage surge (3+ garbage rows sent in sequence)
- Near-death survival (board above row 16, then cleared to below 10)
- Elimination moment
- Comeback (went from last place to winning)
- Perfect clear (entire board empty after line clear)

Layer 2 — LLM narrative commentary:
- Detected events fed to LLM with game context
- LLM generates engaging commentary for each key moment
- Used in replay viewer, tournament highlights, and spectator mode
- Example: "Player Alex executes a devastating T-spin double while under 6 rows of garbage pressure, sending 4 lines to Bob who was already at height 17 — elimination follows 2 seconds later."

**Database schema additions:**

```
tournaments (id, name, format, status, max_players, config_json, created_at, starts_at)
tournament_registrations (id, tournament_id, user_id, seed, registered_at)
tournament_groups (id, tournament_id, group_number)
tournament_group_members (id, group_id, user_id, points, wins, losses, tiebreaker_json)
tournament_matches (id, tournament_id, stage, round, match_number, status, config_json)
tournament_match_players (id, match_id, user_id, score, placement)
replays (id, match_id, tournament_id, game_type_id, event_log, metadata_json, expires_at)
replay_key_moments (id, replay_id, tick, event_type, description, llm_commentary)
```

**Key deliverables:**
- Tournament creation and management (admin UI)
- Registration flow with capacity limits
- Group stage engine (round-robin scheduling, standings, tiebreakers)
- Knockout bracket engine (seeding, advancement, best-of-N)
- Live tournament bracket view (spectator-friendly)
- Replay recording and storage with retention policy
- Replay viewer with playback controls
- Heuristic key-moment detection module
- LLM commentary integration (async, non-blocking)
- Tournament results and statistics page

---

### P7 — Content & Community

**Goal:** Social features, content creation tools, and community engagement.

**Features:**
- Player profiles with customization (avatars, banners, titles earned from tournaments)
- Friends list and party system
- In-game chat (lobby + spectator, not during gameplay to avoid distraction)
- Clip system: save and share short replay clips of key moments
- Player statistics and achievements
- Community leaderboards (weekly, monthly, all-time)
- Tournament highlight reels (auto-generated from key moments)

**Replay sharing:**
- Generate shareable links for any replay or clip
- Embed support (iframe for external sites)
- Social media preview cards (Open Graph metadata with game thumbnail)

---

### P8 — Advanced Bot Intelligence

**Goal:** Sophisticated bot behavior that adapts in real-time and provides meaningful practice partners.

**Live micro-adjustments:**
- After each game, Phoenix worker process evaluates bot performance
- Weight adjustments computed based on game outcome vs expected performance
- Workers run in-process within Phoenix, scaling horizontally with the Fly.io cluster
- No separate worker infrastructure needed — scales with game server capacity
- Adjustment magnitude decreases over time (learning rate decay)

**Personality archetypes:**
- Aggressive: high attack_bonus, danger_aggression weights
- Defensive: high survival_height, garbage_pressure weights
- Balanced: even weight distribution
- Chaotic: higher mutation in weight selection per game
- Each archetype is a starting point; micro-adjustments personalize from there

**Practice mode features:**
- Bot difficulty auto-matches player ELO
- "Challenge" mode: bot set slightly above player's level
- Post-game analysis: what the bot would have done differently at key moments
- Training scenarios: practice against specific garbage patterns, speed levels

---

### P9 — CI/CD & Quality Infrastructure

**Goal:** Comprehensive quality gates and deployment automation.

**`verify-task` pipeline:**

```yaml
verify-task:
  steps:
    - name: Compile
      run: mix compile --warnings-as-errors
    - name: Format check
      run: mix format --check-formatted
    - name: Linter
      run: mix credo --strict
    - name: Server tests
      run: mix test
    - name: Client lint
      run: cd client && npx oxlint src/
    - name: Client format
      run: cd client && npx prettier --check "src/**/*.{ts,tsx,js,jsx,css}"
    - name: Client tests
      run: cd client && npm test -- --watchAll=false
    - name: Acceptance criteria
      run: ./scripts/verify-acceptance.sh  # Task-specific checks
```

**All checks must pass.** The verify-task is the quality gate for every PR and every task completion.

**Deployment pipeline (extends existing CI/CD design):**
- PR guard: manual dispatch, runs verify-task
- Release: tag-triggered, builds Docker image → GHCR → Fly.io deploy
- Staging environment: auto-deploy from `develop` branch
- Production: manual promotion from staging after verification

**Fly.io clustering:**
- Multi-region deployment for low latency
- Erlang distribution for cross-node communication
- Clustered Phoenix PubSub for game state broadcasts
- Sticky sessions for WebSocket connections (Fly.io handles this natively)

---

## Architecture Overview

### System Architecture

```
                    ┌─────────────────────────────────────┐
                    │           Fly.io Cluster             │
                    │                                     │
  Client ──WSS──→  │  ┌─────────┐    ┌─────────┐        │
  (React)          │  │ Phoenix  │←──→│ Phoenix  │        │
                    │  │ Node 1  │    │ Node 2   │        │
                    │  └────┬────┘    └────┬────┘        │
                    │       │              │              │
                    │       └──────┬───────┘              │
                    │              │                      │
                    │       ┌──────┴──────┐               │
                    │       │ PostgreSQL  │               │
                    │       │   (Fly PG)  │               │
                    │       └─────────────┘               │
                    └─────────────────────────────────────┘
```

### Supervision Tree (Platform)

```
Platform.Supervisor (one_for_one)
├── PlatformWeb.Telemetry
├── Phoenix.PubSub (name: Platform.PubSub)
├── Platform.Repo (Ecto/PostgreSQL)
├── Registry (Platform.GameRegistry, :unique)
├── Platform.GameSupervisor (DynamicSupervisor)
│   └── [Game plugin processes — e.g., Tetris.GameRoom]
├── Platform.Matchmaking.Supervisor
│   ├── Platform.Matchmaking.RankedQueue
│   └── Platform.Matchmaking.CasualQueue
├── Platform.Tournament.Supervisor (DynamicSupervisor)
│   └── [Tournament processes]
├── Platform.BotWorker.Supervisor
│   └── [Bot weight adjustment workers]
├── Platform.Lobby (GenServer)
└── PlatformWeb.Endpoint
```

### Data Flow

```
Player Input → WebSocket → Phoenix Channel → Game Plugin (via SDK behaviour)
    → Game State Update → Broadcast to all players/spectators
    → Metrics recorded → DB (async)
    → Replay events logged → DB (async)

Matchmaking Queue → Match Found → Create Game Room → Notify Players
    → Game Complete → ELO Update → Metrics Update → Replay Finalize

Tournament Engine → Schedule Matches → Create Game Rooms
    → Collect Results → Update Standings → Advance Bracket
    → Generate Key Moments → LLM Commentary (async)
```

---

## Phase Dependencies

```
P1 (Platform Shell) ──→ P2 (Matchmaking) ──→ P3 (Spectator)
       │                       │                    │
       │                       ↓                    │
       ├──────────────→ P4 (Bot Metrics) ──→ P5 (Chain Evolution)
       │                                            │
       │                       ┌────────────────────┘
       │                       ↓
       ├──────────────→ P6 (Tournaments) ──→ P7 (Content/Community)
       │
       ├──────────────→ P8 (Advanced Bots) ← P5
       │
       └──────────────→ P9 (CI/CD) [can run in parallel with any phase]
```

**P9 (CI/CD) should start early** — the verify-task pipeline benefits all subsequent phases.

---

## Open Items (Deferred)

| Item | Notes | When to Revisit |
|------|-------|-----------------|
| Monetization | Important but deferred; identify monetized moments later | After P7 |
| Mobile native apps | Web-first is decided; native wrapping (Capacitor/PWA) | After P3 |
| SDK documentation | Public SDK docs for third-party devs | During P1, publish after P6 |
| Anti-cheat | Server-authoritative handles most; advanced detection needed at scale | P6 (tournaments) |
| Moderation | Chat moderation, reporting, bans | P7 |
| Analytics dashboard | Platform-wide metrics (DAU, retention, match counts) | P2 |
| Infrastructure cost modeling | Fly.io pricing at scale, DB sizing | Before P6 |
| Legal/compliance | Terms of service, privacy policy, GDPR | Before public launch |

---

## Decisions Log

All decisions recorded during brainstorming session on 2026-02-19:

| # | Question | Decision |
|---|----------|----------|
| Q1 | Solo mode architecture | Keep client-side for now, migrate to server later |
| Q2 | Target platform | Web-first, responsive for mobile |
| Q3 | Deployment target | Fly.io with Erlang clustering |
| Q4 | Authentication strategy | OAuth (Google/GitHub/Discord) + guest play |
| Q5 | Database | PostgreSQL |
| Q6 | Matchmaking approach | ELO-based with skill tiers |
| Q7 | Spectator mode | Yes, built into P3 |
| Q8 | Bot difficulty model | Continuous slider (0.0-1.0), not discrete levels |
| Q9 | Bot/human metrics | All 14 metrics (8 solo + 6 battle) + generation; same metrics for humans |
| Q10 | Chain evolution | Confirmed — multi-generation lineage tracking |
| Q11 | Multi-game architecture | Shell + game plugin from P1; SDK for third-party devs; marketplace for players |
| Q12 | Tournament format | 48 players → 12 groups of 4, round-robin, top 2 advance → 24-player knockout |
| Q13 | Replay storage | Server-side with retention policy; per-tournament folder; event log format |
| Q14 | Analytical engine | Both: heuristics detect events, LLM narrates them |
| Q15 | Bot weight workers | In-process Phoenix workers, scale with cluster |
| Q16 | verify-task scope | Tests pass, code compiles, linter passes, format check passes, acceptance criteria met |
