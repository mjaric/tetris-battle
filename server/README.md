# Tetris Server

Phoenix/Elixir backend for multiplayer Tetris. Server-authoritative: all game logic runs server-side, clients send inputs and render state.

## Setup

```bash
mix setup        # Install dependencies
mix phx.server   # Start dev server on :4000
mix test         # Run tests
```

## Bot Weight Evolution

### Solo (Hard difficulty)

Train optimal heuristic weights (8 features) for the Hard difficulty bot using a genetic algorithm.

```bash
# Quick test run
mix bot.evolve --population 10 --generations 5 --games 3

# Full run
mix bot.evolve --population 50 --generations 100 --games 30

# Distributed (with remote worker)
mix bot.evolve --workers worker@192.168.1.50 --cookie tetris_evo
```

Results: `priv/bot_weights.json` (auto-loaded by Hard bots), `priv/bot_evolution_log.csv` (for charting).

### Battle

Train battle-aware bot weights (14 features) with multiplayer context: garbage pressure, attack incentives, survival, and opponent awareness.

```bash
# Quick test run
mix bot.evolve.battle --population 6 --generations 3 --battles 5

# Full run
mix bot.evolve.battle --population 30 --generations 15 --battles 20

# Distributed
mix bot.evolve.battle --workers worker@192.168.1.50 --cookie tetris_evo
```

Results: `priv/battle_weights.json` (auto-loaded by Battle bots), `priv/battle_evolution_log.csv`.

Battle evolution uses adaptive opponents (solo-trained bots initially, switching to co-evolution on stagnation).

See `docs/notes/bot-evolution.md` for full documentation.
