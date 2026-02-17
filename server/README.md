# Tetris Server

Phoenix/Elixir backend for multiplayer Tetris. Server-authoritative: all game logic runs server-side, clients send inputs and render state.

## Setup

```bash
mix setup        # Install dependencies
mix phx.server   # Start dev server on :4000
mix test         # Run tests
```

## Bot Weight Evolution

Train optimal heuristic weights for the Hard difficulty bot using a genetic algorithm.

```bash
# Quick test run
mix bot.evolve --population 10 --generations 5 --games 3

# Full run
mix bot.evolve --population 50 --generations 100 --games 30

# Distributed (with remote worker)
mix bot.evolve --workers worker@192.168.1.50 --cookie tetris_evo
```

Results are saved to `priv/bot_weights.json` (auto-loaded by Hard bots) and `priv/bot_evolution_log.csv` (for charting).

See `docs/notes/bot-evolution.md` for full documentation.
