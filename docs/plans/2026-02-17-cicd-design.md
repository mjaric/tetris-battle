# CI/CD Design — GitHub Actions

Date: 2026-02-17

## Overview

Two GitHub Actions workflows: a manually dispatched PR guard and a tag-triggered release
pipeline. The React SPA is bundled into the Elixir/Phoenix release so a single Docker image
serves both the API and static frontend. Nginx sits in front for TLS termination only.

## Workflows

### PR Guard — `.github/workflows/ci.yml`

Triggered by `workflow_dispatch` (manual dispatch only). Must pass before merging to main —
enforced via GitHub branch protection requiring `client-checks` and `server-checks` status checks.

Three jobs:

1. **`detect-changes`** — runs `git diff --name-only origin/main...HEAD`, outputs
   `client_changed` and `server_changed` booleans
2. **`client-checks`** — conditional on `client_changed`, runs in parallel with server-checks
3. **`server-checks`** — conditional on `server_changed`, runs in parallel with client-checks

### Release Build — `.github/workflows/release.yml`

Triggered on `push` to tags matching `v*` (e.g. `v1.0.0`). Builds Docker image and pushes to
GitHub Container Registry (`ghcr.io/<org>/tetris:<tag>`). Uses built-in `GITHUB_TOKEN` — no
manual credentials needed.

## Docker — Multi-Stage Build

**Stage 1: `client-builder` (node:22-slim)**
- `npm ci && npm run build` in the `client/` directory
- Outputs compiled SPA to `/client/build`

**Stage 2: `server-builder` (hexpm/elixir:1.18.x-erlang-27.x-debian-bookworm-slim)**
- Fetches Mix deps (`--only prod`)
- Copies SPA build from stage 1 into `priv/static/`
- Runs `MIX_ENV=prod mix release` producing a self-contained OTP release

**Stage 3: `runtime` (debian:bookworm-slim)**
- Copies only the OTP release binary from stage 2
- Installs only runtime system libs (`libstdc++6`, `openssl`)
- No Elixir, Erlang, or Node at runtime

### Runtime Environment Variables

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `SECRET_KEY_BASE` | Yes | — | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Yes | `localhost` | Public hostname for URL generation |
| `PORT` | No | `4000` | HTTP listen port |
| `CORS_ORIGINS` | No | — | If set, enables CORS headers in Phoenix plug |
| `DATABASE_URL` | No | — | Unused now, ready for future DB |

## Static File Serving

Phoenix serves the React SPA via `Plug.Static` pointed at `priv/static/`. A catch-all router
route serves `index.html` for any request that is not an API or WebSocket route, allowing
React Router to handle client-side navigation.

Nginx proxies all traffic to Phoenix and handles TLS termination. It does not serve static
files directly.

## Linting & Formatting

### Client

- **Prettier** — `printWidth: 120`, `tabWidth: 2`, `semi: true`, `singleQuote: true`
- **Oxlint** — strict mode; `max-lines-per-function: error (max: 100)`, `no-unused-vars: error`
- **Jest** — unit tests via `npm test -- --watchAll=false`

CI steps (all must pass):
1. `npx prettier --check "src/**/*.{ts,tsx,js,jsx,css}"`
2. `npx oxlint src/`
3. `npm test -- --watchAll=false`

### Server

- **`mix format`** — `line_length: 120` in `.formatter.exs`
- **Credo** — `MaxLineLength: 120`, `FunctionLength: 100` in `.credo.exs`
- **ExUnit** — `mix test`

CI steps (all must pass):
1. `mix format --check-formatted`
2. `mix credo --strict`
3. `mix test`

## Files Created / Modified

New files:
```
.github/workflows/ci.yml
.github/workflows/release.yml
Dockerfile
client/.prettierrc
client/oxlint.json
server/.credo.exs
server/priv/static/.gitkeep
```

Modified files:
```
server/.formatter.exs              — add line_length: 120
server/mix.exs                     — add credo as dev/test dep
server/lib/tetris_web/endpoint.ex  — update Plug.Static config
server/lib/tetris_web/router.ex    — add SPA catch-all route
server/lib/tetris_web/controllers/page_controller.ex  — serves index.html (new)
```

## Branch Protection Setup (Manual, post-merge)

GitHub Settings → Branches → main → require status checks before merging:
- `client-checks`
- `server-checks`
