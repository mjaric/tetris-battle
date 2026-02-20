# CLAUDE.md — Client (React/TypeScript)

## Prerequisites

- Node.js (see `package-lock.json` for lockfile version)
- npm

## Development Commands

```bash
npm install                  # Install dependencies
npm run dev                  # Vite dev server on :3000
npm run build                # TypeScript check (tsc -b) + Vite production build
npm run preview              # Preview production build
npm run lint                 # OxLint (src/)
npm run format               # Prettier (write)
npm run format:check         # Prettier (check only)
```

## Dependencies

### Runtime

| Dependency | Purpose | Docs |
|---|---|---|
| react ^19.2 | UI framework | https://react.dev |
| react-dom ^19.2 | React DOM renderer | https://react.dev |
| react-router ^7.13 | Client-side routing | https://reactrouter.com |
| phoenix ^1.8 | Phoenix JS client (WebSocket channels) | https://hexdocs.pm/phoenix/js |

### Dev

| Dependency | Purpose | Docs |
|---|---|---|
| vite ^7.3 | Build tool & dev server | https://vite.dev |
| typescript ~5.9 | Type checking | https://www.typescriptlang.org |
| tailwindcss ^4.1 | Utility-first CSS | https://tailwindcss.com |
| @tailwindcss/vite ^4.1 | Tailwind Vite plugin | https://tailwindcss.com/docs/installation/vite |
| @vitejs/plugin-react ^5.1 | React fast refresh for Vite | https://github.com/vitejs/vite-plugin-react |
| oxlint 1.48 | Fast linter | https://oxc.rs/docs/guide/usage/linter |
| prettier 3.8 | Code formatter | https://prettier.io |

When looking up documentation for any dependency, use `mcp__context7__resolve-library-id` and `mcp__context7__query-docs` tools. These work for all client libraries (React, Vite, Tailwind, react-router, etc.).

## Project Structure

```
src/
  App.tsx                    # Root component, screen state machine
  main.tsx                   # Entry point, React root render
  index.css                  # Global styles (Tailwind imports)
  constants.ts               # Tetromino shapes, colors, SRS wall kick data
  types.ts                   # Shared TypeScript types
  phoenix.d.ts               # Type declarations for phoenix JS client
  components/
    MainMenu.tsx             # Start screen (solo / multiplayer)
    NicknameForm.tsx         # Player name input
    Lobby.tsx                # Room list, create/join rooms
    WaitingRoom.tsx          # Pre-game room (players list, start button)
    GameSession.tsx          # Active multiplayer game container
    SoloGame.tsx             # Solo mode game container
    Board.tsx                # Tetris board renderer (single board)
    MultiBoard.tsx           # Multi-player board layout
    PlayerBoard.tsx          # Individual player board in multiplayer
    NextPiece.tsx            # Next piece preview
    Sidebar.tsx              # Game sidebar (score, level, lines)
    StatBox.tsx              # Individual stat display
    Results.tsx              # Game over results screen
    TargetIndicator.tsx      # Garbage target selector
    AudioControls.tsx        # Sound toggle UI
    LatencyIndicator.tsx     # Network latency display
  hooks/
    useTetris.ts             # Solo game loop (client-only, no server)
    useSocket.ts             # Phoenix WebSocket connection lifecycle
    useChannel.ts            # Phoenix channel join/leave lifecycle
    useMultiplayerGame.ts    # Multiplayer state management + input dispatch
    useAnimations.ts         # CSS animations for game events
    useSoundEffects.ts       # Sound playback for game events
    useGameEvents.ts         # Game event detection (line clears, etc.)
    useLatency.ts            # Server latency measurement
  context/
    GameContext.tsx           # React context for game state
  audio/
    SoundManager.ts          # Audio playback engine
  utils/
    calculateCellSize.ts     # Board cell size calculation
    dangerZone.ts            # Board danger zone detection
```

## Architecture Notes

### Screen Flow

`App.tsx` manages a state machine: `menu` -> `solo` | `nickname` -> `lobby` -> `waiting` -> `playing` -> `results`

### Solo vs Multiplayer

- **Solo mode** (`useTetris` hook): Game loop runs entirely client-side. No server connection needed. Piece generation, gravity, collision, line clearing all happen in the browser.
- **Multiplayer mode** (`useMultiplayerGame` hook): Client sends keyboard inputs to server via Phoenix channels. Server processes all game logic and broadcasts state back. Client only renders.

### Phoenix Channel Integration

- `useSocket` manages the WebSocket connection to `ws://localhost:4000/socket`
- `useChannel` handles joining/leaving specific channels (`lobby:main`, `game:{room_id}`)
- The `phoenix` npm package provides the JS client for Phoenix channels

### Key Patterns

- All game types/interfaces are in `types.ts`
- Tetromino shapes, rotation states, colors, and SRS wall kick tables are in `constants.ts` (duplicated from server)
- Board dimensions: 10 wide x 20 tall
- Tailwind CSS 4 is used for styling (utility classes, no CSS modules)

## Code Style

- Prettier: 120 char line width, 2-space indent, single quotes, trailing commas (es5), semicolons
- OxLint plugins: `react`, `react-hooks`, `typescript`
- Max 100 lines per function (OxLint rule, excludes comments and blank lines)
- TypeScript strict mode with additional checks (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noPropertyAccessFromIndexSignature`)
- Run `npm run format` before committing
- Run `npm run lint` to check for issues

## TypeScript Configuration

- Target: ES2022
- JSX: react-jsx (automatic runtime)
- Module: ESNext with bundler resolution
- Strict mode enabled with all additional strict checks
- `verbatimModuleSyntax: true` — use `import type` for type-only imports
- `erasableSyntaxOnly: true` — no enums or parameter properties
