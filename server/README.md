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

## TetrisGPT Training

TetrisGPT is a decoder-only transformer (~121K parameters) that learns placement strategy from recorded bot-vs-bot games. It uses Nx, Axon, EXLA, and Polaris.

The pipeline has three steps: record training data, train the model, then benchmark.

### Step 1: Record Training Data

Record 4-player bot-vs-bot battles. Each game captures per-player timelines of board states, piece types, battle context, and placement decisions.

```bash
mix tetris_gpt.record [options]
```

| Option | Default | Description |
|---|---|---|
| `--games`, `-g` | 100 | Number of 4-player bot battles to record |
| `--difficulty`, `-d` | hard | Bot difficulty: `hard` or `battle` |
| `--output`, `-o` | `priv/tetris_gpt/data` | Output directory |

The recorder generates sliding-window sequences (64 timesteps each) and saves them to `sequences.bin` in the output directory.

```bash
# Quick test
mix tetris_gpt.record --games 10

# Full dataset
mix tetris_gpt.record --games 100 --difficulty hard
```

### Step 2: Train the Model

Train the transformer on the recorded sequences. Uses cross-entropy loss over 40 placement classes with Adam optimizer.

```bash
mix tetris_gpt.train [options]
```

| Option | Default | Description |
|---|---|---|
| `--epochs` | 50 | Training epochs |
| `--batch-size` | 32 | Batch size |
| `--lr` | 3e-4 | Learning rate |
| `--data` | `priv/tetris_gpt/data/sequences.bin` | Training data path |
| `--output` | `priv/tetris_gpt/checkpoints` | Output directory for model params |

The trainer does a 90/10 train/validation split and saves final parameters to `final_params.nx` in the output directory.

```bash
# Quick test
mix tetris_gpt.train --epochs 5 --batch-size 16

# Full training
mix tetris_gpt.train --epochs 50 --batch-size 32 --lr 3e-4
```

### Step 3: Benchmark

Evaluate a trained model against heuristic bots.

```bash
mix tetris_gpt.benchmark [options]
```

| Option | Default | Description |
|---|---|---|
| `--games` | 20 | Number of benchmark games |
| `--checkpoint` | *(required)* | Model checkpoint path |
| `--opponents` | easy | Opponent difficulty: `easy`, `medium`, or `hard` |

```bash
mix tetris_gpt.benchmark --checkpoint priv/tetris_gpt/checkpoints/final_params.nx --games 20
```

### End-to-End Example

```bash
# Record 100 games, train for 50 epochs, benchmark
mix tetris_gpt.record --games 100
mix tetris_gpt.train --epochs 50
mix tetris_gpt.benchmark --checkpoint priv/tetris_gpt/checkpoints/final_params.nx
```

### Model Configuration

Default hyperparameters (defined in `TetrisGpt.Model.Transformer.default_config/0`):

| Parameter | Value | Description |
|---|---|---|
| `d_model` | 64 | Internal representation width |
| `n_heads` | 4 | Parallel attention heads |
| `d_ff` | 256 | Feed-forward hidden width (4x d_model) |
| `n_layers` | 2 | Decoder blocks |
| `max_seq_len` | 64 | Context window (timesteps) |
| `num_placements` | 40 | Output classes (4 rotations x 10 columns) |
| `dropout` | 0.1 | Regularization rate |

### Files

| Path | Purpose |
|---|---|
| `priv/tetris_gpt/data/sequences.bin` | Recorded training sequences |
| `priv/tetris_gpt/checkpoints/final_params.nx` | Trained model parameters (auto-loaded by GPT bots) |

See `docs/plans/2026-02-22-tetris-gpt-design.md` for full architecture documentation.
