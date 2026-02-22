# UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the Tetris client from flat dark UI to a polished glassmorphism gaming dashboard with a reusable component library and dev showcase route.

**Architecture:** CSS-only approach — update Tailwind v4 theme tokens, add glass utility classes, create 8 reusable primitives, wrap everything in a sidebar app shell with ambient background. No new runtime dependencies. Google Fonts loaded via `<link>` in `index.html`.

**Tech Stack:** React 19, Tailwind CSS 4, Vite 7, TypeScript 5.9, Google Fonts (Space Grotesk, Inter, JetBrains Mono)

---

## Task 1: Design System Foundation — Theme Tokens & Fonts

**Files:**
- Modify: `client/index.html`
- Modify: `client/src/index.css`

**Step 1: Add Google Fonts to index.html**

Replace the contents of `<head>` in `client/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/vite.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600;700&family=Space+Grotesk:wght@500;600;700&display=swap"
      rel="stylesheet"
    />
    <title>Tetris Battle</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

**Step 2: Update Tailwind theme tokens in index.css**

Replace the `@theme` block and `body` rule in `client/src/index.css` with:

```css
@import 'tailwindcss';

@theme {
  /* Backgrounds */
  --color-bg-primary: #07071a;
  --color-bg-secondary: rgba(20, 20, 50, 0.6);
  --color-bg-tertiary: rgba(30, 30, 60, 0.4);
  --color-bg-cell: #0f0f23;
  --color-bg-elevated: #2a2a4a;

  /* Accents */
  --color-accent: #7c6cff;
  --color-cyan: #00e0e0;
  --color-green: #00b894;
  --color-amber: #ffa502;
  --color-red: #ff4757;

  /* Medals */
  --color-gold: #ffd700;
  --color-silver: #c0c0c0;
  --color-bronze: #cd7f32;

  /* Text */
  --color-text-primary: #e8e8f0;
  --color-text-muted: rgba(255, 255, 255, 0.5);
  --color-muted: #888;

  /* Glass */
  --color-glass-border: rgba(255, 255, 255, 0.08);
  --color-glass-highlight: rgba(255, 255, 255, 0.04);
  --color-border: #333;

  /* Fonts */
  --font-display: 'Space Grotesk', system-ui, sans-serif;
  --font-body: 'Inter', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, monospace;
}

body {
  margin: 0;
  font-family: var(--font-body);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background-color: var(--color-bg-primary);
  color: var(--color-text-primary);
  overflow: hidden;
}
```

**Step 3: Add glass utility classes after the body rule**

Add these right after the `body { ... }` block, before the keyframes:

```css
/* === Glass Utilities === */

.glass {
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  background: var(--color-bg-secondary);
  border: 1px solid var(--color-glass-border);
  border-radius: 1rem;
}

.glass-elevated {
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  background: var(--color-bg-tertiary);
  border: 1px solid var(--color-glass-border);
  border-radius: 0.75rem;
  box-shadow:
    0 8px 32px rgba(0, 0, 0, 0.3),
    0 0 0 1px var(--color-glass-highlight) inset;
}

.glass-subtle {
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 0.5rem;
}

/* === Page Transition === */

@keyframes page-enter {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.page-enter {
  animation: page-enter 200ms ease-out both;
}
```

**Step 4: Add accessibility rules at the end of the file**

Append to the existing `@media (prefers-reduced-motion: reduce)` block:

```css
  .page-enter {
    animation: none !important;
  }
```

Add after the reduced-motion block:

```css
@media (prefers-contrast: more) {
  .glass,
  .glass-elevated,
  .glass-subtle {
    border-color: rgba(255, 255, 255, 0.2);
  }

  body {
    color: #fff;
  }
}
```

**Step 5: Verify dev server runs**

Run: `cd client && npm run dev`
Expected: Vite starts on port 3000, no CSS errors in console

**Step 6: Commit**

```bash
git add client/index.html client/src/index.css
git commit -m "feat(ui): add design system tokens, fonts, and glass utilities"
```

---

## Task 2: Ambient Background Component

**Files:**
- Create: `client/src/components/ui/AmbientBackground.tsx`

**Step 1: Create the ambient background component**

Create `client/src/components/ui/AmbientBackground.tsx`:

```tsx
export default function AmbientBackground() {
  return (
    <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
      {/* Purple orb — top left */}
      <div
        className="absolute -left-32 -top-32 h-[500px] w-[500px] rounded-full opacity-15"
        style={{
          background:
            'radial-gradient(circle, #7c6cff 0%, transparent 70%)',
          filter: 'blur(120px)',
        }}
      />
      {/* Cyan orb — bottom right */}
      <div
        className="absolute -bottom-40 -right-40 h-[400px] w-[400px] rounded-full opacity-10"
        style={{
          background:
            'radial-gradient(circle, #00e0e0 0%, transparent 70%)',
          filter: 'blur(100px)',
        }}
      />
      {/* Warm orb — mid left */}
      <div
        className="absolute left-1/4 top-1/2 h-[300px] w-[300px] rounded-full opacity-[0.07]"
        style={{
          background:
            'radial-gradient(circle, #ffa502 0%, transparent 70%)',
          filter: 'blur(80px)',
        }}
      />
    </div>
  );
}
```

**Step 2: Commit**

```bash
git add client/src/components/ui/AmbientBackground.tsx
git commit -m "feat(ui): add AmbientBackground component with gradient orbs"
```

---

## Task 3: GlassCard Component

**Files:**
- Create: `client/src/components/ui/GlassCard.tsx`

**Step 1: Create GlassCard**

Create `client/src/components/ui/GlassCard.tsx`:

```tsx
import type { ReactNode } from 'react';

type GlassVariant = 'default' | 'elevated' | 'subtle';
type PaddingSize = 'none' | 'sm' | 'md' | 'lg';

interface GlassCardProps {
  variant?: GlassVariant;
  padding?: PaddingSize;
  glow?: string;
  className?: string;
  children: ReactNode;
  onClick?: () => void;
}

const VARIANT_CLASS: Record<GlassVariant, string> = {
  default: 'glass',
  elevated: 'glass-elevated',
  subtle: 'glass-subtle',
};

const PADDING_CLASS: Record<PaddingSize, string> = {
  none: '',
  sm: 'p-3',
  md: 'p-5',
  lg: 'p-8',
};

export default function GlassCard({
  variant = 'default',
  padding = 'md',
  glow,
  className = '',
  children,
  onClick,
}: GlassCardProps) {
  const glowStyle = glow
    ? { boxShadow: `0 0 20px ${glow}` }
    : undefined;

  return (
    <div
      className={[
        VARIANT_CLASS[variant],
        PADDING_CLASS[padding],
        onClick
          ? 'cursor-pointer transition-all duration-150 hover:border-accent/30'
          : '',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      style={glowStyle}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={
        onClick
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onClick();
              }
            }
          : undefined
      }
    >
      {children}
    </div>
  );
}
```

**Step 2: Commit**

```bash
git add client/src/components/ui/GlassCard.tsx
git commit -m "feat(ui): add GlassCard component"
```

---

## Task 4: Button Component

**Files:**
- Create: `client/src/components/ui/Button.tsx`

**Step 1: Create Button**

Create `client/src/components/ui/Button.tsx`:

```tsx
import type { ReactNode, ButtonHTMLAttributes } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'danger' | 'ghost';
type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  fullWidth?: boolean;
  icon?: ReactNode;
  children: ReactNode;
}

const VARIANT_CLASS: Record<ButtonVariant, string> = {
  primary: [
    'text-white font-semibold',
    'bg-gradient-to-r from-accent to-cyan/80',
    'hover:brightness-110 hover:scale-[1.02]',
    'active:scale-[0.98]',
    'shadow-[0_0_16px_rgba(124,108,255,0.3)]',
    'hover:shadow-[0_0_24px_rgba(124,108,255,0.5)]',
  ].join(' '),
  secondary: [
    'glass-subtle text-text-primary',
    'hover:brightness-110 hover:scale-[1.02]',
    'active:scale-[0.98]',
  ].join(' '),
  danger: [
    'text-white font-semibold',
    'bg-red/20 border border-red/40',
    'hover:bg-red/30 hover:scale-[1.02]',
    'active:scale-[0.98]',
  ].join(' '),
  ghost: [
    'text-text-muted',
    'hover:text-text-primary hover:bg-white/[0.03]',
    'active:scale-[0.98]',
  ].join(' '),
};

const SIZE_CLASS: Record<ButtonSize, string> = {
  sm: 'px-3 py-1.5 text-sm rounded-lg gap-1.5',
  md: 'px-5 py-2.5 text-base rounded-xl gap-2',
  lg: 'px-8 py-3.5 text-lg rounded-xl gap-2.5',
};

export default function Button({
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  icon,
  children,
  disabled,
  className = '',
  ...rest
}: ButtonProps) {
  return (
    <button
      className={[
        'inline-flex items-center justify-center',
        'transition-all duration-150',
        'focus-visible:outline-2 focus-visible:outline-accent',
        'focus-visible:outline-offset-2',
        VARIANT_CLASS[variant],
        SIZE_CLASS[size],
        fullWidth ? 'w-full' : '',
        disabled ? 'cursor-not-allowed opacity-50' : '',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      disabled={disabled}
      {...rest}
    >
      {icon && <span className="shrink-0">{icon}</span>}
      {children}
    </button>
  );
}
```

**Step 2: Commit**

```bash
git add client/src/components/ui/Button.tsx
git commit -m "feat(ui): add Button component with variants"
```

---

## Task 5: Input Component

**Files:**
- Create: `client/src/components/ui/Input.tsx`

**Step 1: Create Input**

Create `client/src/components/ui/Input.tsx`:

```tsx
import type { InputHTMLAttributes, ReactNode } from 'react';

interface InputProps
  extends InputHTMLAttributes<HTMLInputElement> {
  icon?: ReactNode;
  error?: string;
  label?: string;
}

export default function Input({
  icon,
  error,
  label,
  className = '',
  id,
  ...rest
}: InputProps) {
  const inputId = id ?? label?.toLowerCase().replace(/\s+/g, '-');

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label
          htmlFor={inputId}
          className="font-body text-sm text-text-muted"
        >
          {label}
        </label>
      )}
      <div className="relative">
        {icon && (
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted">
            {icon}
          </span>
        )}
        <input
          id={inputId}
          className={[
            'glass-subtle w-full px-3 py-2.5 text-text-primary',
            'placeholder:text-text-muted/50',
            'transition-all duration-150',
            'focus:border-accent/50 focus:outline-none',
            'focus:shadow-[0_0_0_2px_rgba(124,108,255,0.2)]',
            icon ? 'pl-10' : '',
            error ? 'border-red/50' : '',
            className,
          ]
            .filter(Boolean)
            .join(' ')}
          {...rest}
        />
      </div>
      {error && (
        <p className="text-sm text-red">{error}</p>
      )}
    </div>
  );
}
```

**Step 2: Commit**

```bash
git add client/src/components/ui/Input.tsx
git commit -m "feat(ui): add Input component with error state"
```

---

## Task 6: Badge, Avatar, Stat, Divider Components

**Files:**
- Create: `client/src/components/ui/Badge.tsx`
- Create: `client/src/components/ui/Avatar.tsx`
- Create: `client/src/components/ui/Stat.tsx`
- Create: `client/src/components/ui/Divider.tsx`

**Step 1: Create Badge**

Create `client/src/components/ui/Badge.tsx`:

```tsx
import type { ReactNode } from 'react';

type BadgeVariant = 'player' | 'bot' | 'rank' | 'status';

interface BadgeProps {
  variant?: BadgeVariant;
  color?: string;
  children: ReactNode;
  className?: string;
}

const VARIANT_STYLES: Record<BadgeVariant, string> = {
  player: 'bg-accent/20 text-accent border-accent/30',
  bot: 'bg-amber/20 text-amber border-amber/30',
  rank: 'bg-gold/20 text-gold border-gold/30',
  status: 'bg-green/20 text-green border-green/30',
};

export default function Badge({
  variant = 'status',
  color,
  children,
  className = '',
}: BadgeProps) {
  const colorStyle = color
    ? {
        backgroundColor: `${color}20`,
        color,
        borderColor: `${color}4d`,
      }
    : undefined;

  return (
    <span
      className={[
        'inline-flex items-center gap-1',
        'rounded-full border px-2 py-0.5',
        'text-xs font-medium',
        !color ? VARIANT_STYLES[variant] : '',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      style={colorStyle}
    >
      {children}
    </span>
  );
}
```

**Step 2: Create Avatar**

Create `client/src/components/ui/Avatar.tsx`:

```tsx
type AvatarSize = 'sm' | 'md' | 'lg';

interface AvatarProps {
  name: string;
  size?: AvatarSize;
  status?: boolean;
  className?: string;
}

const SIZE_CLASS: Record<AvatarSize, string> = {
  sm: 'h-7 w-7 text-xs',
  md: 'h-9 w-9 text-sm',
  lg: 'h-12 w-12 text-base',
};

function hashColor(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  const hue = Math.abs(hash) % 360;
  return `hsl(${hue}, 65%, 55%)`;
}

export default function Avatar({
  name,
  size = 'md',
  status,
  className = '',
}: AvatarProps) {
  const color = hashColor(name);
  const letter = name.charAt(0).toUpperCase();

  return (
    <div className={`relative inline-flex ${className}`}>
      <div
        className={[
          SIZE_CLASS[size],
          'flex items-center justify-center',
          'rounded-full font-display font-bold text-white',
        ].join(' ')}
        style={{
          background: `linear-gradient(135deg, ${color}, ${color}88)`,
        }}
        aria-label={name}
      >
        {letter}
      </div>
      {status != null && (
        <span
          className={[
            'absolute bottom-0 right-0',
            'h-2.5 w-2.5 rounded-full border-2 border-bg-primary',
            status ? 'bg-green' : 'bg-muted',
          ].join(' ')}
        />
      )}
    </div>
  );
}
```

**Step 3: Create Stat**

Create `client/src/components/ui/Stat.tsx`:

```tsx
interface StatProps {
  label: string;
  value: string | number;
  mono?: boolean;
  className?: string;
}

export default function Stat({
  label,
  value,
  mono = true,
  className = '',
}: StatProps) {
  return (
    <div className={`flex flex-col gap-0.5 ${className}`}>
      <span className="font-body text-xs uppercase tracking-wider text-text-muted">
        {label}
      </span>
      <span
        className={[
          'text-lg font-bold text-text-primary',
          mono ? 'font-mono' : 'font-display',
        ].join(' ')}
      >
        {value}
      </span>
    </div>
  );
}
```

**Step 4: Create Divider**

Create `client/src/components/ui/Divider.tsx`:

```tsx
interface DividerProps {
  label?: string;
  className?: string;
}

export default function Divider({
  label,
  className = '',
}: DividerProps) {
  if (label) {
    return (
      <div
        className={`flex items-center gap-3 ${className}`}
      >
        <div className="h-px flex-1 bg-glass-border" />
        <span className="text-xs text-text-muted">
          {label}
        </span>
        <div className="h-px flex-1 bg-glass-border" />
      </div>
    );
  }

  return (
    <div className={`h-px bg-glass-border ${className}`} />
  );
}
```

**Step 5: Commit**

```bash
git add client/src/components/ui/Badge.tsx client/src/components/ui/Avatar.tsx client/src/components/ui/Stat.tsx client/src/components/ui/Divider.tsx
git commit -m "feat(ui): add Badge, Avatar, Stat, and Divider components"
```

---

## Task 7: NavItem Component & Sidebar

**Files:**
- Create: `client/src/components/ui/NavItem.tsx`
- Create: `client/src/components/ui/AppSidebar.tsx`

**Step 1: Create NavItem**

Create `client/src/components/ui/NavItem.tsx`:

```tsx
import { useNavigate, useLocation } from 'react-router';
import type { ReactNode } from 'react';

interface NavItemProps {
  icon: ReactNode;
  label: string;
  to: string;
  collapsed?: boolean;
}

export default function NavItem({
  icon,
  label,
  to,
  collapsed = false,
}: NavItemProps) {
  const navigate = useNavigate();
  const location = useLocation();
  const active = location.pathname === to;

  return (
    <button
      onClick={() => navigate(to)}
      title={collapsed ? label : undefined}
      className={[
        'flex w-full items-center gap-3 rounded-lg px-3 py-2.5',
        'transition-all duration-150',
        'focus-visible:outline-2 focus-visible:outline-accent',
        active
          ? 'glass-subtle border-l-2 border-l-accent text-text-primary'
          : 'text-text-muted hover:text-text-primary hover:bg-white/[0.03]',
        collapsed ? 'justify-center' : '',
      ]
        .filter(Boolean)
        .join(' ')}
      aria-current={active ? 'page' : undefined}
    >
      <span className="shrink-0 text-lg">{icon}</span>
      {!collapsed && (
        <span className="font-body text-sm font-medium">
          {label}
        </span>
      )}
    </button>
  );
}
```

**Step 2: Create AppSidebar**

Create `client/src/components/ui/AppSidebar.tsx`:

```tsx
import { useState } from 'react';
import NavItem from './NavItem.tsx';
import Avatar from './Avatar.tsx';
import { useAuthContext } from '../../platform/auth/AuthProvider.tsx';

interface AppSidebarProps {
  hidden?: boolean;
}

export default function AppSidebar({
  hidden = false,
}: AppSidebarProps) {
  const [collapsed, setCollapsed] = useState(true);
  const { user } = useAuthContext();

  if (hidden) return null;

  const displayName =
    user?.nickname ?? user?.displayName ?? 'Player';

  return (
    <aside
      className={[
        'glass fixed left-0 top-0 z-40 flex h-screen flex-col',
        'border-r border-glass-border rounded-none rounded-r-2xl',
        'transition-all duration-200',
        collapsed ? 'w-[72px]' : 'w-[220px]',
      ].join(' ')}
      onMouseEnter={() => setCollapsed(false)}
      onMouseLeave={() => setCollapsed(true)}
    >
      {/* Logo */}
      <div className="flex h-16 items-center justify-center border-b border-glass-border">
        <span className="font-display text-xl font-bold text-accent">
          {collapsed ? 'T' : 'TETRIS'}
        </span>
      </div>

      {/* Navigation */}
      <nav className="flex flex-1 flex-col gap-1 p-3">
        <NavItem
          icon="🏠"
          label="Home"
          to="/"
          collapsed={collapsed}
        />
        <NavItem
          icon="🎮"
          label="Solo Play"
          to="/solo"
          collapsed={collapsed}
        />
        <NavItem
          icon="⚔️"
          label="Lobby"
          to="/lobby"
          collapsed={collapsed}
        />
      </nav>

      {/* User */}
      <div className="border-t border-glass-border p-3">
        <div
          className={[
            'flex items-center gap-3',
            collapsed ? 'justify-center' : '',
          ].join(' ')}
        >
          <Avatar name={displayName} size="sm" />
          {!collapsed && (
            <span className="truncate font-body text-sm text-text-primary">
              {displayName}
            </span>
          )}
        </div>
      </div>
    </aside>
  );
}
```

**Step 3: Commit**

```bash
git add client/src/components/ui/NavItem.tsx client/src/components/ui/AppSidebar.tsx
git commit -m "feat(ui): add NavItem and AppSidebar components"
```

---

## Task 8: App Shell Layout

**Files:**
- Create: `client/src/components/ui/AppShell.tsx`
- Create: `client/src/components/ui/PageTransition.tsx`
- Modify: `client/src/App.tsx`

**Step 1: Create PageTransition wrapper**

Create `client/src/components/ui/PageTransition.tsx`:

```tsx
import type { ReactNode } from 'react';

interface PageTransitionProps {
  children: ReactNode;
  className?: string;
}

export default function PageTransition({
  children,
  className = '',
}: PageTransitionProps) {
  return (
    <div className={`page-enter ${className}`}>
      {children}
    </div>
  );
}
```

**Step 2: Create AppShell layout**

Create `client/src/components/ui/AppShell.tsx`:

```tsx
import type { ReactNode } from 'react';
import AppSidebar from './AppSidebar.tsx';
import AmbientBackground from './AmbientBackground.tsx';

interface AppShellProps {
  children: ReactNode;
  hideSidebar?: boolean;
}

export default function AppShell({
  children,
  hideSidebar = false,
}: AppShellProps) {
  return (
    <div className="flex min-h-screen">
      <AmbientBackground />
      <AppSidebar hidden={hideSidebar} />
      <main
        className={[
          'flex-1 overflow-auto',
          hideSidebar ? '' : 'ml-[72px]',
        ]
          .filter(Boolean)
          .join(' ')}
      >
        {children}
      </main>
    </div>
  );
}
```

**Step 3: Update App.tsx to use AppShell**

Modify `client/src/App.tsx`. Wrap routes in AppShell. Game routes (`/solo`, `/room/:roomId`) pass `hideSidebar`. The full replacement:

```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router';
import { AuthProvider, useAuthContext } from './platform/auth/AuthProvider.tsx';
import { GameProvider, useGameContext } from './context/GameContext.tsx';
import LoginScreen from './platform/auth/LoginScreen.tsx';
import AuthCallback from './platform/auth/AuthCallback.tsx';
import RegisterPage from './platform/auth/RegisterPage.tsx';
import MainMenu from './components/MainMenu.tsx';
import SoloGame from './components/SoloGame.tsx';
import Lobby from './components/Lobby.tsx';
import GameSession from './components/GameSession.tsx';
import AppShell from './components/ui/AppShell.tsx';
import type { ReactNode } from 'react';

function RequireAuth({ children }: { children: ReactNode }) {
  const { isAuthenticated, loading } = useAuthContext();
  if (loading) return null;
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function RequireSocket({ children }: { children: ReactNode }) {
  const { connected } = useGameContext();
  if (!connected) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <p className="text-text-muted">Connecting...</p>
      </div>
    );
  }
  return <>{children}</>;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginScreen />} />
      <Route path="/oauth/callback" element={<AuthCallback />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <AppShell>
              <MainMenu />
            </AppShell>
          </RequireAuth>
        }
      />
      <Route
        path="/solo"
        element={
          <AppShell hideSidebar>
            <SoloGame />
          </AppShell>
        }
      />
      <Route
        path="/lobby"
        element={
          <RequireAuth>
            <RequireSocket>
              <AppShell>
                <Lobby />
              </AppShell>
            </RequireSocket>
          </RequireAuth>
        }
      />
      <Route
        path="/room/:roomId"
        element={
          <RequireAuth>
            <RequireSocket>
              <AppShell hideSidebar>
                <GameSession />
              </AppShell>
            </RequireSocket>
          </RequireAuth>
        }
      />
      {/* Dev component showcase — only in dev mode */}
      {import.meta.env.DEV && (
        <Route
          path="/dev/components"
          element={
            <AppShell>
              <></>
            </AppShell>
          }
        />
      )}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <GameProvider>
          <AppRoutes />
        </GameProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
```

**Step 4: Verify the app renders**

Run: `cd client && npm run dev`
Navigate to `http://localhost:3000` — should see the sidebar with ambient background.

**Step 5: Commit**

```bash
git add client/src/components/ui/AppShell.tsx client/src/components/ui/PageTransition.tsx client/src/App.tsx
git commit -m "feat(ui): add AppShell layout with sidebar and ambient background"
```

---

## Task 9: Component Barrel Export

**Files:**
- Create: `client/src/components/ui/index.ts`

**Step 1: Create barrel export**

Create `client/src/components/ui/index.ts`:

```ts
export { default as GlassCard } from './GlassCard.tsx';
export { default as Button } from './Button.tsx';
export { default as Input } from './Input.tsx';
export { default as Badge } from './Badge.tsx';
export { default as Avatar } from './Avatar.tsx';
export { default as Stat } from './Stat.tsx';
export { default as Divider } from './Divider.tsx';
export { default as NavItem } from './NavItem.tsx';
export { default as AppSidebar } from './AppSidebar.tsx';
export { default as AppShell } from './AppShell.tsx';
export { default as AmbientBackground } from './AmbientBackground.tsx';
export { default as PageTransition } from './PageTransition.tsx';
```

**Step 2: Commit**

```bash
git add client/src/components/ui/index.ts
git commit -m "feat(ui): add barrel export for UI components"
```

---

## Task 10: Dev Component Showcase Route

**Files:**
- Create: `client/src/components/dev/ComponentShowcase.tsx`
- Modify: `client/src/App.tsx`

**Step 1: Create ComponentShowcase page**

Create `client/src/components/dev/ComponentShowcase.tsx`:

```tsx
import {
  GlassCard,
  Button,
  Input,
  Badge,
  Avatar,
  Stat,
  Divider,
  PageTransition,
} from '../ui/index.ts';

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-12">
      <h2 className="mb-1 font-display text-2xl font-bold text-text-primary">
        {title}
      </h2>
      <p className="mb-4 text-sm text-text-muted">
        {description}
      </p>
      <div className="flex flex-wrap items-start gap-4">
        {children}
      </div>
    </section>
  );
}

export default function ComponentShowcase() {
  return (
    <PageTransition className="min-h-screen p-8">
      <h1 className="mb-2 font-display text-4xl font-bold text-text-primary">
        Component Library
      </h1>
      <p className="mb-10 text-text-muted">
        All reusable UI primitives with variants
      </p>

      {/* Typography */}
      <Section
        title="Typography"
        description="Font families: Space Grotesk (display), Inter (body), JetBrains Mono (mono)"
      >
        <div className="flex flex-col gap-3">
          <span className="font-display text-4xl font-bold">
            Space Grotesk Display
          </span>
          <span className="font-body text-lg">
            Inter Body Text — The quick brown fox jumps
          </span>
          <span className="font-mono text-lg">
            JetBrains Mono — 1234567890
          </span>
        </div>
      </Section>

      {/* Colors */}
      <Section
        title="Colors"
        description="Design token color palette"
      >
        <div className="flex flex-wrap gap-3">
          {[
            ['bg-accent', 'Accent'],
            ['bg-cyan', 'Cyan'],
            ['bg-green', 'Green'],
            ['bg-amber', 'Amber'],
            ['bg-red', 'Red'],
            ['bg-gold', 'Gold'],
            ['bg-silver', 'Silver'],
            ['bg-bronze', 'Bronze'],
          ].map(([bg, name]) => (
            <div
              key={name}
              className="flex flex-col items-center gap-1"
            >
              <div
                className={`${bg} h-12 w-12 rounded-lg`}
              />
              <span className="text-xs text-text-muted">
                {name}
              </span>
            </div>
          ))}
        </div>
      </Section>

      {/* Glass Cards */}
      <Section
        title="GlassCard"
        description="Three glass levels: default, elevated, subtle"
      >
        <GlassCard padding="md">
          <p className="text-sm">Default glass</p>
        </GlassCard>
        <GlassCard variant="elevated" padding="md">
          <p className="text-sm">Elevated glass</p>
        </GlassCard>
        <GlassCard variant="subtle" padding="md">
          <p className="text-sm">Subtle glass</p>
        </GlassCard>
        <GlassCard
          padding="md"
          glow="rgba(124, 108, 255, 0.3)"
        >
          <p className="text-sm">With accent glow</p>
        </GlassCard>
        <GlassCard
          padding="md"
          onClick={() => {}}
        >
          <p className="text-sm">Clickable card</p>
        </GlassCard>
      </Section>

      {/* Buttons */}
      <Section
        title="Button"
        description="Variants: primary, secondary, danger, ghost. Sizes: sm, md, lg"
      >
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="primary" size="sm">
              Primary SM
            </Button>
            <Button variant="primary" size="md">
              Primary MD
            </Button>
            <Button variant="primary" size="lg">
              Primary LG
            </Button>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="secondary">Secondary</Button>
            <Button variant="danger">Danger</Button>
            <Button variant="ghost">Ghost</Button>
            <Button variant="primary" disabled>
              Disabled
            </Button>
          </div>
          <Button variant="primary" fullWidth>
            Full Width
          </Button>
        </div>
      </Section>

      {/* Inputs */}
      <Section
        title="Input"
        description="Text input with optional label, icon, error state"
      >
        <div className="flex w-full max-w-md flex-col gap-4">
          <Input
            label="Nickname"
            placeholder="Enter nickname..."
          />
          <Input
            label="With icon"
            placeholder="Search..."
            icon={<span>🔍</span>}
          />
          <Input
            label="Error state"
            placeholder="Invalid..."
            error="This field is required"
          />
        </div>
      </Section>

      {/* Badges */}
      <Section
        title="Badge"
        description="Variants: player, bot, rank, status"
      >
        <Badge variant="player">Player</Badge>
        <Badge variant="bot">Bot</Badge>
        <Badge variant="rank">1st</Badge>
        <Badge variant="status">Online</Badge>
        <Badge color="#ff69b4">Custom</Badge>
      </Section>

      {/* Avatars */}
      <Section
        title="Avatar"
        description="Sizes: sm, md, lg. Deterministic color from name hash"
      >
        <Avatar name="Alice" size="sm" />
        <Avatar name="Bob" size="md" />
        <Avatar name="Charlie" size="lg" />
        <Avatar name="Diana" size="md" status={true} />
        <Avatar name="Eve" size="md" status={false} />
      </Section>

      {/* Stats */}
      <Section
        title="Stat"
        description="Label + value display for scores and metrics"
      >
        <Stat label="Score" value={12500} />
        <Stat label="Lines" value={42} />
        <Stat label="Level" value={7} />
        <Stat label="Time" value="02:34" />
        <Stat label="Player" value="Alice" mono={false} />
      </Section>

      {/* Dividers */}
      <Section
        title="Divider"
        description="Horizontal separator with optional label"
      >
        <div className="flex w-full max-w-md flex-col gap-6">
          <Divider />
          <Divider label="OR" />
          <Divider label="SECTION" />
        </div>
      </Section>
    </PageTransition>
  );
}
```

**Step 2: Update App.tsx dev route**

In `client/src/App.tsx`, add the import at the top (conditional) and update the dev route:

Add lazy import near the top imports:

```tsx
import { lazy, Suspense } from 'react';

const ComponentShowcase = import.meta.env.DEV
  ? lazy(() => import('./components/dev/ComponentShowcase.tsx'))
  : null;
```

Replace the dev route placeholder `<></>` with:

```tsx
{import.meta.env.DEV && ComponentShowcase && (
  <Route
    path="/dev/components"
    element={
      <AppShell>
        <Suspense fallback={null}>
          <ComponentShowcase />
        </Suspense>
      </AppShell>
    }
  />
)}
```

**Step 3: Verify showcase renders**

Run: `cd client && npm run dev`
Navigate to `http://localhost:3000/dev/components`
Expected: All components render with their variants visible on a scrollable page with ambient background and sidebar.

**Step 4: Commit**

```bash
git add client/src/components/dev/ComponentShowcase.tsx client/src/App.tsx
git commit -m "feat(ui): add /dev/components showcase route"
```

---

## Task 11: Redesign LoginScreen

**Files:**
- Modify: `client/src/platform/auth/LoginScreen.tsx`

**Step 1: Read the current LoginScreen**

Read: `client/src/platform/auth/LoginScreen.tsx`

**Step 2: Rewrite LoginScreen using UI components**

Rewrite the component to use `GlassCard`, `Button`, `Divider`, `AmbientBackground`, `PageTransition`. The screen is pre-auth so it doesn't use AppShell (no sidebar). Key elements:

- Centered layout with `AmbientBackground`
- `GlassCard` containing the login form
- Logo/title at top using `font-display`
- OAuth buttons as `Button ghost` with provider brand colors
- `Divider label="OR"`
- Guest button as `Button secondary`

Preserve all existing auth logic (`useAuth`, `useAuthContext`, `useNavigate`, `useEffect` for redirect). Only change the JSX/styling.

**Step 3: Verify login page renders**

Run: `cd client && npm run dev`
Navigate to `http://localhost:3000/login`
Expected: Glassmorphism login card centered on screen with gradient orbs behind it.

**Step 4: Commit**

```bash
git add client/src/platform/auth/LoginScreen.tsx
git commit -m "feat(ui): redesign LoginScreen with glassmorphism"
```

---

## Task 12: Redesign RegisterPage

**Files:**
- Modify: `client/src/platform/auth/RegisterPage.tsx`

**Step 1: Read the current RegisterPage**

Read: `client/src/platform/auth/RegisterPage.tsx`

**Step 2: Rewrite using UI components**

Use `GlassCard`, `Input`, `Button`, `Badge` (for nickname status), `AmbientBackground`, `PageTransition`. Pre-auth screen, no sidebar.

Preserve: all nickname validation logic, debounced availability check, form submission, error handling.

**Step 3: Verify register page renders**

Run: `cd client && npm run dev`
Navigate to `http://localhost:3000/register`
Expected: Glass card with form inputs, status badges for nickname availability.

**Step 4: Commit**

```bash
git add client/src/platform/auth/RegisterPage.tsx
git commit -m "feat(ui): redesign RegisterPage with glassmorphism"
```

---

## Task 13: Redesign MainMenu

**Files:**
- Modify: `client/src/components/MainMenu.tsx`

**Step 1: Read the current MainMenu**

Read: `client/src/components/MainMenu.tsx`

**Step 2: Rewrite using UI components**

Use `GlassCard`, `Button`, `PageTransition`. Remove the old `flex min-h-screen` outer wrapper since the component now renders inside `AppShell`.

Layout: Two large `GlassCard` side by side for Solo Play and Multiplayer. Each card has an icon, title (font-display), short description, and a `Button primary`. Player info shown above.

Preserve: `useAuth` hook usage, navigation, guest upgrade links.

**Step 3: Verify menu renders**

Run: `cd client && npm run dev`
Navigate to `http://localhost:3000/`
Expected: Two glass cards side by side with sidebar visible.

**Step 4: Commit**

```bash
git add client/src/components/MainMenu.tsx
git commit -m "feat(ui): redesign MainMenu with glassmorphism cards"
```

---

## Task 14: Redesign Lobby

**Files:**
- Modify: `client/src/components/Lobby.tsx`

**Step 1: Read the current Lobby**

Read: `client/src/components/Lobby.tsx`

**Step 2: Rewrite using UI components**

Use `GlassCard`, `Button`, `Input`, `Badge`, `PageTransition`. Remove old flex wrapper.

Layout: Page header with title + "Create Room" button. Room list as stacked `GlassCard` items showing room name, player count `Badge`, status `Badge`. Create room form in a `GlassCard elevated` (toggled by the button). Back button as `Button ghost`.

Preserve: all channel logic, room listing, create/join handlers.

**Step 3: Verify lobby renders**

Run: `cd client && npm run dev`
Navigate to `http://localhost:3000/lobby`
Expected: Glass cards for room list, create form in elevated glass card.

**Step 4: Commit**

```bash
git add client/src/components/Lobby.tsx
git commit -m "feat(ui): redesign Lobby with glassmorphism"
```

---

## Task 15: Redesign WaitingRoom

**Files:**
- Modify: `client/src/components/WaitingRoom.tsx`

**Step 1: Read the current WaitingRoom**

Read: `client/src/components/WaitingRoom.tsx`

**Step 2: Rewrite using UI components**

Use `GlassCard`, `Button`, `Badge`, `Avatar`, `Divider`, `PageTransition`.

Layout: `GlassCard` containing player list (Avatar + name + bot/host badges per row), difficulty selector, and action buttons (Start, Leave, Add Bot).

Preserve: all channel logic, bot management, difficulty selection, host-only controls.

**Step 3: Verify waiting room renders**

Navigate to a game room in waiting state.
Expected: Glass card with player list, avatars, badges.

**Step 4: Commit**

```bash
git add client/src/components/WaitingRoom.tsx
git commit -m "feat(ui): redesign WaitingRoom with glassmorphism"
```

---

## Task 16: Redesign Results Screen

**Files:**
- Modify: `client/src/components/Results.tsx`

**Step 1: Read the current Results**

Read: `client/src/components/Results.tsx`

**Step 2: Rewrite using UI components**

Use `GlassCard`, `Button`, `Badge`, `Avatar`, `Stat`, `PageTransition`.

Layout: Stacked `GlassCard` per player. Winner card gets accent glow. Each card shows: rank medal Badge, Avatar, nickname, Stat components for score/lines/eliminations.

Preserve: ranking logic, back navigation.

**Step 3: Verify results render**

Complete a game and check the results screen.
Expected: Glass cards with medal badges and stat displays.

**Step 4: Commit**

```bash
git add client/src/components/Results.tsx
git commit -m "feat(ui): redesign Results screen with glassmorphism"
```

---

## Task 17: Redesign Solo Game HUD

**Files:**
- Modify: `client/src/components/Sidebar.tsx`
- Modify: `client/src/components/SoloGame.tsx`

**Step 1: Read current Sidebar and SoloGame**

Read: `client/src/components/Sidebar.tsx`
Read: `client/src/components/SoloGame.tsx`

**Step 2: Rewrite Sidebar using UI components**

Use `GlassCard`, `Stat`, `Divider`. The sidebar becomes a `GlassCard elevated` containing:
- NextPiece at top
- Divider
- Stat components for score, level, lines
- Divider
- Controls legend in text-muted

**Step 3: Rewrite SoloGame layout**

Wrap the board in a `GlassCard` with subtle inner glow. Replace the old flex wrapper (no `min-h-screen bg-bg-primary` — the AppShell handles that). Game over and pause overlays use a frosted glass backdrop (`glass` + fixed position).

Preserve: all game logic, keyboard events, sound effects, animation hooks.

**Step 4: Verify solo game renders**

Navigate to `http://localhost:3000/solo`
Expected: Board in glass card, stats sidebar in elevated glass card, no sidebar nav visible.

**Step 5: Commit**

```bash
git add client/src/components/Sidebar.tsx client/src/components/SoloGame.tsx
git commit -m "feat(ui): redesign solo game HUD with glassmorphism"
```

---

## Task 18: Redesign Multiplayer Board Framing

**Files:**
- Modify: `client/src/components/PlayerBoard.tsx`
- Modify: `client/src/components/MultiBoard.tsx`
- Modify: `client/src/components/GameSession.tsx`

**Step 1: Read current PlayerBoard, MultiBoard, GameSession**

Read: `client/src/components/PlayerBoard.tsx`
Read: `client/src/components/MultiBoard.tsx`
Read: `client/src/components/GameSession.tsx`

**Step 2: Update PlayerBoard**

Wrap each player board in a `GlassCard` with dynamic glow based on `glowLevel`. Replace the existing border styling. Use `Stat` components for the mini HUD stats below the board. Use `Badge` for bot indicator.

Keep: all glow level logic, danger zone rendering, latency indicator, cell rendering, event animations.

**Step 3: Update MultiBoard**

Replace outer wrapper. Keep the responsive layout logic and dynamic cell sizing unchanged. The glass card wrapping is handled by PlayerBoard.

**Step 4: Update GameSession**

Minimal changes — the component routes to WaitingRoom, MultiBoard, or Results. Ensure it works within AppShell (hideSidebar=true). Update the loading/connecting states to use glass styling.

**Step 5: Verify multiplayer renders**

Create a room, add bots, start a game.
Expected: Each player board in a glass card with glow effects, stats below boards.

**Step 6: Commit**

```bash
git add client/src/components/PlayerBoard.tsx client/src/components/MultiBoard.tsx client/src/components/GameSession.tsx
git commit -m "feat(ui): redesign multiplayer board framing with glassmorphism"
```

---

## Task 19: Board Component Glass Frame

**Files:**
- Modify: `client/src/components/Board.tsx`

**Step 1: Read current Board**

Read: `client/src/components/Board.tsx`

**Step 2: Update Board styling**

The Board component renders the 10x20 grid. Wrap the grid container in glass styling. Replace the existing `border-3 border-accent` with a glass border and subtle inner glow shadow.

Keep: all cell rendering, ghost piece styling, animation classes, event overlay.

**Step 3: Verify board renders**

Start a solo game — board should have glass frame instead of hard purple border.

**Step 4: Commit**

```bash
git add client/src/components/Board.tsx
git commit -m "feat(ui): redesign Board component with glass frame"
```

---

## Task 20: Lint, Format, Type Check

**Files:**
- All modified/created files

**Step 1: Run formatter**

Run: `cd client && npm run format`

**Step 2: Run linter**

Run: `cd client && npm run lint`
Fix any issues found.

**Step 3: Run type check**

Run: `cd client && npx tsc -b --noEmit`
Fix any type errors.

**Step 4: Run build**

Run: `cd client && npm run build`
Expected: Clean build with no errors.

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "style: fix lint and format issues from UI redesign"
```

---

## Task 21: Visual Verification Pass

**Files:** None (verification only)

**Step 1: Verify all screens visually**

Walk through each screen in the browser:

1. `/login` — Glass card centered, OAuth buttons, ambient orbs
2. `/register` — Glass card with form, nickname status
3. `/` — MainMenu with two glass cards, sidebar visible
4. `/solo` — Game board in glass frame, stats in elevated glass card, sidebar hidden
5. `/lobby` — Room list as glass cards, create form
6. Join a room — WaitingRoom with player list, avatars, badges
7. Start a game — Multiplayer boards in glass cards with glow
8. Finish a game — Results with medal badges, stats
9. `/dev/components` — All components visible with all variants

**Step 2: Check accessibility**

- Tab through all interactive elements — focus rings should be visible (accent color)
- Enable `prefers-reduced-motion: reduce` in DevTools — transitions should be disabled
- Verify text contrast meets WCAG AA on glass backgrounds

**Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "fix(ui): visual polish from verification pass"
```
