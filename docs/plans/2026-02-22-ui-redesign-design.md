# UI Redesign: Glassmorphism Gaming Dashboard

**Date:** 2026-02-22
**Scope:** Full visual overhaul — all screens including in-game HUD
**Approach:** CSS-only (no new runtime dependencies)
**Dependencies added:** Google Fonts (Space Grotesk, Inter, JetBrains Mono)

## Design System Foundation

### Color Palette

| Token | Value | Usage |
|-------|-------|-------|
| `--bg-primary` | `#07071a` | Page background |
| `--bg-secondary` | `rgba(20, 20, 50, 0.6)` | Glass card fill |
| `--bg-tertiary` | `rgba(30, 30, 60, 0.4)` | Nested glass panels |
| `--accent` | `#7c6cff` | Primary interactive |
| `--accent-gradient` | `linear-gradient(135deg, #7c6cff, #00b4d8)` | Buttons, highlights |
| `--cyan` | `#00e0e0` | Secondary accent, garbage, targeting |
| `--glass-border` | `rgba(255, 255, 255, 0.08)` | Glass card edges |
| `--glass-highlight` | `rgba(255, 255, 255, 0.04)` | Subtle top-edge shine |
| `--text-primary` | `#e8e8f0` | Body text |
| `--text-muted` | `rgba(255, 255, 255, 0.5)` | Secondary labels |

Tetromino colors unchanged (canonical Tetris palette).

### Typography

- **Display/Headings:** Space Grotesk — geometric, modern, gaming feel
- **Body:** Inter — clean readability at small sizes
- **Mono (scores/stats):** JetBrains Mono — tabular numbers

### Glassmorphism Primitives

Three reusable glass levels as Tailwind utilities:

- `.glass` — `backdrop-blur-md bg-bg-secondary border border-glass-border rounded-2xl`
- `.glass-elevated` — `backdrop-blur-lg bg-bg-tertiary border border-glass-border rounded-xl shadow-lg`
- `.glass-subtle` — `backdrop-blur-sm bg-white/[0.03] border border-white/[0.05] rounded-lg`

### Background Ambient Effects

- Two or three fixed-position gradient orbs (purple top-left, cyan bottom-right, optional warm mid-left)
- Each orb: `position: fixed`, `border-radius: 50%`, `filter: blur(100-150px)`, opacity 0.1-0.15
- CSS noise texture overlay at 2-3% opacity (small tiling PNG, ~4KB)
- Orbs are static — no animation, zero GPU cost

## Layout Structure

### App Shell

Persistent sidebar on the left, content area fills the rest. Sidebar hides during active gameplay.

### Sidebar

- **Width:** 72px collapsed (icons only), 220px expanded (icons + labels)
- **Style:** `glass` with left-edge gradient highlight
- **Top:** App logo/icon
- **Nav items:** Home, Solo Play, Lobby — icon + label, active state uses accent gradient left border
- **Bottom:** User avatar/nickname, settings gear
- **Hover behavior:** Expands from 72px to 220px with smooth transition, or stays expanded on wider viewports
- **In-game:** Hidden, with small floating toggle in corner

### Content Area

- Padding: `p-6` to `p-8`
- Fills available space, no max-width constraint
- Ambient gradient orbs fixed behind content

### In-Game Layout (Solo)

- Sidebar hidden
- Board in a `glass` card with subtle inner glow
- Stats sidebar in a `glass-elevated` card (next piece, score, level, lines, time)
- Overlays (pause, game over) use full-screen frosted glass backdrop

### In-Game Layout (Multiplayer)

- Same responsive scaling logic as current
- Each PlayerBoard wrapped in a `glass` card frame
- Dynamic cell-size calculation unchanged

## Component Library

### Reusable Primitives

**GlassCard**
- Props: `variant` (`default` | `elevated` | `subtle`), `glow` (optional accent color), `padding`
- Renders appropriate glass class with rounded corners, border, backdrop-blur

**Button**
- Props: `variant` (`primary` | `secondary` | `danger` | `ghost`), `size` (`sm` | `md` | `lg`), `fullWidth`, `disabled`, `icon`
- `primary`: accent gradient background, white text, glow on hover
- `secondary`: glass-subtle background, muted border
- `danger`: red tint background, red border
- `ghost`: transparent, hover reveals glass-subtle bg
- All: rounded-xl, hover brightness/scale transition

**Input**
- Props: `variant` (`default` | `search`), `icon`, `error`
- Glass-subtle background, glass-border, focus ring in accent color

**Badge**
- Props: `variant` (`player` | `bot` | `rank` | `status`), `color`
- Small pill, glass-subtle background tinted with variant color

**NavItem**
- Props: `icon`, `label`, `active`, `to`
- Active: accent gradient left border, glass-subtle bg, bright text

**Avatar**
- Props: `name`, `size` (`sm` | `md` | `lg`), `status`
- Deterministic gradient background from name hash, first letter display

**Stat**
- Props: `label`, `value`, `mono` (default true)
- Label in text-muted uppercase, value in JetBrains Mono bold

**Divider**
- Horizontal line with glass-border color, optional centered label

### Screen Compositions

**LoginScreen** — Centered glass card: logo, OAuth buttons (ghost + provider color), divider, guest button.

**MainMenu** — Two large glass cards side by side: Solo Play and Multiplayer. Each with icon, title, description, primary button.

**Lobby** — Room list as stacked GlassCard items (name, player count badge, status badge). Create Room form in GlassCard elevated.

**WaitingRoom** — GlassCard with player list (Avatar + name + badges), room settings, action buttons.

**Results** — Stacked GlassCard per player: rank medal badge, name, stat components. Winner card has accent glow.

**Game HUD (Solo)** — GlassCard elevated for stats sidebar: next piece preview, stat components for score/level/lines/time.

**Game HUD (Multi)** — Each PlayerBoard in GlassCard with dynamic glow. Mini stats below board. Target indicator as pulsing accent border.

## Dev Component Route

- Route: `/dev/components` — only registered when `import.meta.env.DEV` is true
- Single scrollable page with ambient orbs background
- Sections for each component showing all variants side by side
- Section headers with component name + usage note
- Order: Typography > Colors > Buttons > Cards > Inputs > Badges > Avatars > Stats > Compositions

## Transitions & Polish

### Page Transitions

CSS-only: content fades in on route change (`opacity 0->1`, `translateY(8px->0)`, 200ms ease-out). Game screens skip transition for instant render.

### Hover & Interactive States

- Buttons: `brightness(1.1)` + `scale(1.02)` hover, `scale(0.98)` active, 150ms
- Clickable cards: border shifts to `accent/30%` on hover, subtle glow
- Nav items: background fades in, icon brightens, 150ms
- Inputs: focus ring animates in with accent color

### Accessibility

- WCAG AA contrast maintained (text-primary on glass backgrounds)
- Focus-visible outlines with accent color ring
- `prefers-reduced-motion: reduce` disables scale transitions and page fade-ins
- `prefers-contrast: more` increases border opacity and text contrast

## What Stays Unchanged

- All game logic (server-authoritative, tick loop, input handling)
- Board cell rendering and tetromino colors
- All existing game animations (line-clear, shake, float-up, etc.)
- Dynamic cell-size calculation for multiplayer
- Channel protocol and socket connection
- Auth flow (OAuth, guest, JWT)
- Routing structure (paths unchanged, `/dev/components` added)
