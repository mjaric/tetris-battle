# Bot Weight Evolution

Genetic algorithm pipeline for evolving optimal Tetris bot heuristic weights.

## Overview

The bot evaluates placements using six weighted heuristics: aggregate height, holes, bumpiness, lines cleared, max column height, and well sum. The GA evolves these weights by simulating thousands of headless games with pruned 2-piece lookahead, selecting for average lines cleared. Supports distributed evaluation across multiple BEAM nodes via Erlang distribution.

Board analysis is pure Elixir arithmetic, no external ML libraries. A single top-to-bottom pass over the 20x10 grid computes all six metrics.

## Architecture

All training code lives under `BotTrainer` — separate from runtime game code.

| Module | Purpose |
|--------|---------|
| `BotTrainer.Simulation` | Headless game loop (no GenServer, no timing) |
| `BotTrainer.Evolution` | GA engine: selection, crossover, mutation |
| `BotTrainer.Cluster` | Distributed worker node management |
| `Mix.Tasks.Bot.Evolve` | CLI interface with progress output |
| `Tetris.BoardAnalysis` | Pure Elixir board metric computation |

The simulation reuses `Board` and `BotStrategy.enumerate_placements/2` directly, skipping `GameLogic` overhead (no gravity counter, no input queue, no garbage).

## Running

```bash
cd server

# Full run (default: 50 pop x 100 gen x 10 games = 50,000 games)
mix bot.evolve

# Quick test
mix bot.evolve --population 10 --generations 5 --games 3

# Custom params
mix bot.evolve --population 80 --generations 200 --games 20 --concurrency 8
```

### Distributed mode

Distribute evaluation across multiple machines using Erlang distribution. The orchestrator (your dev machine) pushes compiled modules to workers via `:code.load_binary` — workers don't need a copy of your latest code.

**Worker requirements:**
- Erlang/OTP 27 (ERTS 15.2) and Elixir 1.18.1 — must match orchestrator
- Clone repo and compile once: `cd server && mix deps.get && mix compile`

**Start the worker node:**

```bash
./bin/worker.sh <worker-ip> [cookie]
# Example: ./bin/worker.sh 192.168.1.50 tetris_evo
```

**Run with workers from your Mac:**

```bash
mix bot.evolve \
  --workers worker@192.168.1.50 \
  --cookie tetris_evo \
  --population 50 --generations 100 --games 30
```

Multiple workers: `--workers worker@10.0.0.1,worker@10.0.0.2`

Concurrency auto-scales: `schedulers_online * number_of_nodes`.

**Network:** Both machines need bidirectional TCP. Open port 4369 (EPMD) and a distribution port range:

```bash
# On worker, before starting:
export ERL_AFLAGS="-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9200"
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--population N` | 50 | Population size |
| `--generations N` | 100 | Number of generations |
| `--games N` | 10 | Games per genome per generation |
| `--concurrency N` | schedulers x nodes | Max parallel evaluations |
| `--output PATH` | `priv/bot_weights.json` | Output weights file |
| `--log PATH` | `priv/bot_evolution_log.csv` | CSV log file |
| `--tournament N` | 3 | Tournament selection size |
| `--mutation-rate F` | 0.3 | Per-weight mutation probability |
| `--mutation-sigma F` | 0.15 | Gaussian noise std dev |
| `--crossover-rate F` | 0.7 | Crossover probability |
| `--elitism N` | 2 | Elites carried forward unchanged |
| `--immigrants N` | 5 | Random immigrants per generation |
| `--workers NODES` | (none) | Comma-separated worker node names |
| `--cookie COOKIE` | tetris_evo | Erlang distribution cookie |

## Output

**JSON** (`priv/bot_weights.json`) — loaded at runtime by `BotStrategy.weights_for(:hard)`:
```json
{
  "weights": {
    "height": 0.28, "holes": 0.42, "bumpiness": 0.11,
    "lines": 0.19, "max_height": 0.05, "wells": 0.03
  },
  "fitness": 45.2,
  "config": {"population_size": 50, "generations": 100, "games_per_genome": 10},
  "evolved_at": "2026-02-16T15:30:00Z"
}
```

**CSV** (`priv/bot_evolution_log.csv`) — one row per generation for external charting.

## How it works

1. Generate random population of 6-weight vectors (normalized to sum=1.0)
2. Each generation: evaluate all genomes in parallel across cluster (N games each, pruned 2-piece lookahead)
3. Sort by fitness (average lines cleared)
4. Elitism: carry top genomes unchanged
5. Add random immigrants to maintain diversity
6. Fill rest via tournament selection, uniform crossover, Gaussian mutation
7. Normalize all children, repeat

Only `:hard` difficulty uses evolved weights. `:easy` and `:medium` keep hardcoded defaults for intentional difficulty scaling.

## Heuristic features

| Feature | Weight key | Score effect | Description |
|---------|-----------|-------------|-------------|
| Aggregate height | `height` | penalized (-) | Sum of all column heights |
| Holes | `holes` | penalized (-) | Empty cells with filled cells above |
| Bumpiness | `bumpiness` | penalized (-) | Sum of absolute height differences between adjacent columns |
| Lines cleared | `lines` | rewarded (+) | Complete lines from placement |
| Max height | `max_height` | penalized (-) | Height of tallest column |
| Well sum | `wells` | penalized (-) | Sum of well depths — columns lower than both neighbors |

## Pruned lookahead

The simulation uses pruned 2-piece lookahead to balance quality and speed:

1. Score all ~34 candidate placements greedily (current piece only)
2. Take the top 5 candidates
3. For each of those 5, evaluate all ~34 placements of the next piece
4. Pick the candidate with the best combined score

This reduces per-move evaluations from ~1156 (34x34) to ~204 (34 + 5x34), a 5.7x speedup with minimal quality loss.

## Fitness metric

Average lines cleared per game. Higher is better. Games run until board overflow at spawn.

## Performance

Board analysis uses pure Elixir arithmetic with Erlang tuples for O(1) cell access. No external ML libraries (Nx/EXLA were removed). A single `evaluate/1` call processes the 20x10 grid in microseconds.
