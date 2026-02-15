# Multiplayer Tetris Battle Design

## Overview

Add online multiplayer battle mode to the existing single-player Tetris game. Up to 4 players compete in real-time, sending "garbage lines" to targeted opponents. Last player standing wins.

## Architecture

**Server-authoritative model** using Elixir Phoenix Channels with React frontend.

- Server holds all game logic and state (prevents cheating)
- Keyboard inputs are sent to the server via Phoenix Channels
- Server computes game state and broadcasts JSON to all clients every 50ms (20 FPS)
- React frontend renders received state
- Single-player mode remains client-only (unchanged)

```
Keyboard → React → Channel push → GenServer (validate + update) → broadcast JSON → React renders
```

### Backend (Elixir Phoenix)

- **LobbyServer (GenServer):** Registry of active rooms. Handles create/join/list.
- **GameRoom (GenServer):** One per room. Contains all player states, game loop timer (50ms), garbage distribution logic, spectator list.
- **DynamicSupervisor:** Dynamically starts GameRoom processes.
- **Phoenix Channels:** `lobby:main` for lobby operations, `game:{room_id}` for in-game communication.

### Supervisor Tree

```
Application
├── LobbyServer
└── DynamicSupervisor (GameRooms)
    ├── GameRoom {:room_1}
    ├── GameRoom {:room_2}
    └── ...
```

## Game Mechanics

### Garbage Lines

When a player clears N lines simultaneously, the targeted opponent receives N garbage lines:
- Each garbage line is a full row with one random gap (column 0-9)
- Garbage is queued in `pending_garbage` and inserted at the bottom of the opponent's board when they lock their current piece
- Existing rows are pushed upward
- If pushed rows exceed the board height, the player is eliminated

### Target Selection

- **Tab** key cycles through alive opponents
- Current target is visually highlighted on screen
- Garbage goes to the selected target only

### Tick Loop (every 50ms)

1. **Process input queue:** Apply all buffered key events per player (FIFO)
2. **Gravity tick:** Piece falls based on level-dependent timer. Formula: `max(2, 16 - (level - 1))` frames between drops
3. **Process garbage queue:** Garbage lines are inserted when a player locks a piece
4. **Check eliminations:** Board overflow = eliminated, becomes spectator
5. **Broadcast state:** JSON with all player states to all clients in room

### Elimination and Victory

- Eliminated players become spectators (watch remaining players)
- Last player alive wins
- Results screen shows ranking by elimination order, plus stats (score, lines, level)

## Lobby and Authentication

### UI Flow

```
MainMenu → [Solo] → Existing single-player game (unchanged)
         → [Multiplayer] → NicknameScreen → Lobby → GameRoom → Game → Results
```

### Nickname

- Player enters a nickname (3-16 chars, alphanumeric + underscore)
- Stored in localStorage for persistence
- No registration or account system

### Lobby

- Lists active rooms: name, host, player count (e.g. "2/4"), lock icon if password-protected
- "Create Room" button: form with room name, max players (2-4), optional password
- Click room to join (prompts for password if protected)

### Challenge-Response Authentication (password-protected rooms)

```
1. Client → Server: "join_room" {room_id, nickname}
2. Server → Client: "auth_challenge" {nonce: 32 random bytes, base64}
3. Client → Server: "auth_response" {hmac: HMAC-SHA256(password, nonce)}
4. Server: compares with own HMAC-SHA256(stored_password, nonce)
   → "join_accepted" or "join_rejected"
```

- Nonce is single-use, fresh for every attempt
- Password stored in GameRoom GenServer memory only (no database)
- Password disappears when room closes
- Host shares password out-of-band (the app does not distribute it)

## In-Game UI Layout

```
┌──────────────────────────────────────────────────────┐
│  ┌─────────┐   ┌─────────────┐   ┌─────────┐       │
│  │ Player2 │   │   MY BOARD  │   │ Player3 │       │
│  │ (small) │   │   (large)   │   │ (small) │       │
│  │         │   │             │   │         │       │
│  └─────────┘   │             │   └─────────┘       │
│                │             │   ┌─────────┐       │
│  Stats/Next    │             │   │ Player4 │       │
│  Target: P3    │             │   │ (small) │       │
│  [Tab] cycle   └─────────────┘   └─────────┘       │
└──────────────────────────────────────────────────────┘
```

- Player's own board is large and centered
- Opponent boards are small read-only previews on the sides
- Current target has highlighted border
- Tab cycles through alive opponents
- Eliminated players shown grayed out

## State Broadcast Format (JSON)

```json
{
  "tick": 1234,
  "players": {
    "player_id_1": {
      "nickname": "Alex",
      "board": [[0, 0, "cyan", ...], ...],
      "score": 1200,
      "lines": 8,
      "level": 1,
      "alive": true,
      "next_piece": "T",
      "target": "player_id_2"
    }
  },
  "eliminated_order": ["player_id_3"]
}
```

- Board is 2D array: `0` = empty, color string = filled
- Current piece and ghost are composited into the board by the server
- Client only renders the board as-is

## Project Structure

```
tetris/
├── client/                         # React frontend (existing code, relocated)
│   ├── src/
│   │   ├── components/
│   │   │   ├── Board.js            # existing (unchanged)
│   │   │   ├── Sidebar.js          # existing (extended for MP stats)
│   │   │   ├── NextPiece.js        # existing (unchanged)
│   │   │   ├── MainMenu.js         # NEW - Solo/Multiplayer choice
│   │   │   ├── Lobby.js            # NEW - room list, create/join
│   │   │   ├── NicknameForm.js     # NEW
│   │   │   ├── GameRoom.js         # NEW - waiting room before start
│   │   │   ├── MultiBoard.js       # NEW - layout with all boards
│   │   │   ├── MiniBoard.js        # NEW - small opponent preview
│   │   │   ├── TargetIndicator.js  # NEW - current target display
│   │   │   └── Results.js          # NEW - ranking screen
│   │   ├── hooks/
│   │   │   ├── useTetris.js        # existing (single-player, unchanged)
│   │   │   ├── useChannel.js       # NEW - Phoenix Channel wrapper
│   │   │   └── useMultiplayerGame.js # NEW - MP state from channel
│   │   ├── constants.js            # existing
│   │   └── App.js                  # modified - adds routing/screens
│   └── package.json
│
├── server/                         # Elixir Phoenix backend
│   ├── lib/
│   │   ├── tetris/
│   │   │   ├── game_logic.ex       # Tetris rules (move, rotate, clear, etc.)
│   │   │   ├── player_state.ex     # Player state struct
│   │   │   ├── piece.ex            # Tetromino definitions + rotations
│   │   │   ├── board.ex            # Board operations (place, clear, garbage)
│   │   │   └── wall_kicks.ex       # SRS wall kick data
│   │   ├── tetris_game/
│   │   │   ├── game_room.ex        # GenServer - one room
│   │   │   ├── lobby.ex            # GenServer - lobby registry
│   │   │   └── room_supervisor.ex  # DynamicSupervisor for rooms
│   │   └── tetris_web/
│   │       ├── channels/
│   │       │   ├── lobby_channel.ex  # lobby:main channel
│   │       │   └── game_channel.ex   # game:{room_id} channel
│   │       └── endpoint.ex
│   ├── config/
│   └── mix.exs
│
└── README.md
```

## Dependencies

**Frontend:**
- `phoenix` JS client library (Channel communication)
- Existing React stack (unchanged)

**Backend:**
- `phoenix` framework
- `jason` (JSON encoding)
- Standard Elixir/Phoenix stack
- No database - all state in memory (GenServer)

## Error Handling

- WebSocket disconnect: overlay "Reconnecting..." (Phoenix Channel has built-in heartbeat and auto-reconnect)
- Host disconnect: oldest player becomes new host
- GameRoom crash: Supervisor restarts it, players reconnect, game resets
- Input buffering: all key events queued between ticks, processed FIFO - no input lost even with high latency

## Single-Player Mode

- Remains entirely client-side using existing `useTetris` hook
- No server communication
- Accessible from MainMenu
- Completely unchanged from current implementation
