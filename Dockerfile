# ─── Stage 1: Build React SPA ───────────────────────────────────────────────
FROM node:22-slim AS client-builder

WORKDIR /client

COPY client/package*.json ./
RUN npm ci

COPY client/ ./
RUN npm run build

# ─── Stage 2: Build Elixir OTP release ──────────────────────────────────────
FROM hexpm/elixir:1.18.1-erlang-27.2-debian-bookworm-20250113-slim AS server-builder

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Fetch deps first (cached layer if mix.lock unchanged)
COPY server/mix.exs server/mix.lock ./
RUN MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix deps.compile

# Copy server source and inject the React build
COPY server/ ./
COPY --from=client-builder /client/dist ./priv/static

RUN MIX_ENV=prod mix release

# ─── Stage 3: Minimal runtime ────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses5 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=server-builder /app/_build/prod/rel/tetris ./

ENV PHX_HOST=localhost
ENV PORT=4000
ENV MIX_ENV=prod

EXPOSE 4000

CMD ["bin/tetris", "start"]
