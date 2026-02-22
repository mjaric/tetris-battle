# TetrisGPT Design: Neural Network Battle Bot

**Date**: 2026-02-22
**Status**: Approved

## Goal

Build a transformer-based Tetris battle bot ("TetrisGPT") that learns placement
strategy from recorded bot-vs-bot games. Unlike the existing heuristic bots that
evaluate each position independently using weighted metrics, TetrisGPT maintains
temporal context — it remembers the sequence of past board states and actions,
enabling it to form and execute multi-step strategies (stack building, combo
setups, garbage timing).

This is also a learning project: the implementation deliberately uses
transformer concepts (multi-head attention, flash attention, positional
encoding, causal masking) to build hands-on understanding of how LLM-style
architectures work, applied to a concrete game domain.

## Architecture Overview

The system has three layers:

```
Data Layer           Model Layer          Agent Layer
─────────────        ─────────────        ─────────────
GameRecorder         Transformer          GptBotPlayer
DataPipeline         Attention            (GenServer)
                     Flash Attention
(bot v bot           Layers               Plugs into
 replays             Training             existing
 → tensors)                               GameRoom)
```

A `TetrisGPT.Strategy` behaviour defines the interface between Agent and Model
layers, allowing different model implementations to be swapped without changing
the agent.

### Why Three Layers

- **Data** is independent of the model architecture. Recording games and building
  tensors works regardless of whether we train a transformer, CNN, or hybrid.
- **Model** is pure computation. No GenServer state, no game logic, no network IO.
  Given tensors in, returns tensors out.
- **Agent** handles real-time integration: receiving game state broadcasts,
  maintaining the context buffer, calling inference, and submitting actions.

## Input Encoding: How Game State Becomes Tensors

### The Token Concept

In LLMs, each word is a "token" — a vector that represents meaning. In
TetrisGPT, each **piece placement** is a token. It captures everything the model
needs to know about the game at that moment:

| Component | Raw Form | Encoding | Dims |
|-----------|----------|----------|------|
| Board state | 20x10 grid of nil/color | Binary (0=empty, 1=filled), flattened | 200 → Linear → 48 |
| Current piece | atom (:T, :I, etc.) | Learned embedding lookup | 7 → Embedding → 8 |
| Next piece | atom | Learned embedding lookup | 7 → Embedding → 8 |
| Battle context | various integers/floats | Normalized to [0,1] range | 8 |
| Action taken | rotation + column | Learned embedding lookup | 40 → Embedding → 8 |

**Total: 80 features per token**, projected to `d_model=64` via a linear layer.

### Board State Encoding

The 20x10 Tetris board is the most information-dense part of each token.

```
Original board (20 rows x 10 cols):
  . . . . . . . . . .     Row 0  (top)
  . . . . . . . . . .     Row 1
  ...
  . . X X . . . . . .     Row 17
  X X X X . X X X X X     Row 18
  X X X X . X X X X X     Row 19 (bottom)

Binary encoding (same board):
  0 0 0 0 0 0 0 0 0 0
  0 0 0 0 0 0 0 0 0 0
  ...
  0 0 1 1 0 0 0 0 0 0
  1 1 1 1 0 1 1 1 1 1
  1 1 1 1 0 1 1 1 1 1

Flattened: [0, 0, 0, ..., 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, ...]
→ 200-element float32 vector
→ Linear(200, 48) projects to 48 dimensions
```

We discard piece color because it has no strategic value. Whether a cell was
placed by an I-piece or T-piece doesn't affect future play.

### Piece Type Embedding

Rather than one-hot encoding (wasteful at 7 dims), we use a learned embedding
table. The model discovers its own representation for each piece type:

```
Embedding table: 7 piece types × 8 dimensions
  :I → [0.12, -0.34, 0.56, ...]   (8 learned values)
  :O → [0.78, 0.23, -0.11, ...]
  :T → [-0.45, 0.67, 0.89, ...]
  :S → [...]
  :Z → [...]
  :J → [...]
  :L → [...]
```

During training, these embeddings adjust so that pieces with similar strategic
properties (e.g., S and Z are both "awkward" pieces) end up near each other in
embedding space.

### Battle Context Features

8 normalized scalar features that capture the multiplayer situation:

| Feature | Normalization | Why |
|---------|--------------|-----|
| `pending_garbage_count` | / 12 (max practical) | Urgency: incoming garbage |
| `own_max_height` | / 20 (board height) | Danger level |
| `opponent_max_height` | / 20 | Opponent vulnerability |
| `combo_count` | / 10 | Current combo streak |
| `lines_cleared` | / 100 | Game progress |
| `score_diff` | tanh(diff / 1000) | Relative standing |
| `opponent_count` | / 3 | How many opponents alive |
| `alive` | 0 or 1 | Still playing |

### Action Embedding

The placement chosen at each timestep is encoded as an index 0-39:

```
placement_index = rotation * 10 + column
  rotation: 0, 1, 2, 3 (four orientations)
  column: 0-9 (leftmost cell of piece bounding box)

Examples:
  I-piece, no rotation, column 0 → index 0
  T-piece, rotated once, column 5 → index 15
  L-piece, rotated twice, column 8 → index 28
```

Not all 40 indices are valid for every piece (some placements would extend
beyond the board). Invalid placements are masked during inference.

### Sequence Assembly

Each token's 80 features are concatenated and projected:

```
token_t = Linear(
  concat([
    board_projection,      # 48 dims
    current_piece_embed,   # 8 dims
    next_piece_embed,      # 8 dims
    battle_context,        # 8 dims
    action_embed,          # 8 dims
  ]),                      # = 80 dims
  d_model=64
)
```

A sequence of 64 such tokens (last 64 piece placements) forms the model input.
If the game has fewer than 64 placements so far, earlier positions are
zero-padded and masked so the model ignores them.

## Model Architecture: The Transformer

### High-Level Structure

```
Input: {batch, 64, 80}
  ↓ Token projection Linear(80, 64)
  ↓ + Positional encoding (64 × 64 learned)
  ↓
  ╔══════════════════════════╗
  ║ Decoder Block 1          ║
  ║  LayerNorm → MHA → +res ║
  ║  LayerNorm → FFN → +res ║
  ║  Dropout(0.1)            ║
  ╠══════════════════════════╣
  ║ Decoder Block 2          ║
  ║  (same structure)        ║
  ╚══════════════════════════╝
  ↓
  LayerNorm (final)
  ↓ Linear(64, 40)
  ↓ Mask invalid placements → -inf
  ↓ Softmax
Output: {batch, 64, 40} placement probabilities
```

### Hyperparameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `d_model` | 64 | Smallest power-of-2 that can represent board features |
| `n_heads` | 4 | d_model/n_heads = 16 per head, minimum for meaningful attention |
| `d_ff` | 256 | Standard 4x expansion ratio (64 × 4) |
| `n_layers` | 2 | Minimum for learning non-trivial patterns |
| `max_seq_len` | 64 | ~64 piece placements ≈ 2-5 minutes of game |
| `dropout` | 0.1 | Light regularization |
| `vocab_placements` | 40 | 4 rotations × 10 columns |
| Total params | ~110K | Fast CPU inference (<20ms) |

### Positional Encoding

LLMs need to know the order of tokens because attention is inherently
order-agnostic (it's a set operation). We use **learned positional embeddings**:

```
pos_embedding = Nx.tensor of shape {64, 64}  # max_seq × d_model
  Position 0: [0.01, -0.23, ...]  ← learned during training
  Position 1: [0.15, 0.42, ...]
  ...
  Position 63: [-0.33, 0.18, ...]

token_with_position = token_embedding + pos_embedding[position]
```

The alternative (sinusoidal encoding from the original "Attention Is All You
Need" paper) works too, but learned embeddings perform slightly better when the
sequence length is fixed and known, which it is here.

### Pre-Norm vs Post-Norm

We use **pre-norm** (LayerNorm before attention/FFN, not after):

```
Pre-norm (what we use):       Post-norm (original paper):
  x → LayerNorm → Attn → +x    x → Attn → +x → LayerNorm
```

Pre-norm is more stable during training, especially for small models. The
gradients flow more cleanly through the residual connections.

### Multi-Head Attention

This is the core mechanism that lets the model "remember" past states. Here's
how it works step by step:

**1. Project input to Q, K, V (Query, Key, Value):**

```
For each token position, compute three vectors:
  Q = token × W_Q   (what am I looking for?)
  K = token × W_K   (what do I contain?)
  V = token × W_V   (what information do I carry?)

Shapes:
  Input: {batch, 64, 64}        (64 tokens, d_model=64)
  W_Q, W_K, W_V: {64, 64}      (d_model × d_model)
  Q, K, V: {batch, 64, 64}     (64 tokens, d_model=64)
```

**2. Split into multiple heads:**

```
Reshape Q, K, V from {batch, 64, 64} to {batch, 4, 64, 16}
  4 heads, each operating on 16-dim slices

Each head can learn to attend to different things:
  Head 0: might learn to track piece sequences
  Head 1: might learn to track garbage timing
  Head 2: might learn to track board height changes
  Head 3: might learn to track combo streaks
```

**3. Compute attention scores:**

```
For each head:
  scores = (Q × K^T) / sqrt(16)

  This computes how relevant each past position is to each current position.
  Dividing by sqrt(d_k) prevents scores from growing too large.

  scores shape: {batch, 4, 64, 64}
  scores[b][h][i][j] = how much should position i attend to position j?
```

**4. Apply causal mask:**

```
We must prevent the model from "seeing the future":

  mask = upper_triangle_of_ones × -infinity

  Position 0 can only see: [0]
  Position 1 can only see: [0, 1]
  Position 2 can only see: [0, 1, 2]
  ...
  Position 63 can only see: [0, 1, ..., 63]

  scores = scores + mask  (future positions become -inf)
```

**5. Softmax → weighted sum:**

```
  weights = softmax(scores)  → {batch, 4, 64, 64}
  output = weights × V       → {batch, 4, 64, 16}

  Each position's output is a weighted combination of all visible
  past positions' values. Positions the model finds "relevant"
  get higher weights.
```

**6. Concatenate heads and project:**

```
  Reshape {batch, 4, 64, 16} → {batch, 64, 64}  (concat 4 heads)
  output = concat × W_O                           (final projection)
```

### Flash Attention

Standard attention materializes the full 64×64 score matrix in memory. Flash
attention avoids this by computing attention in tiles/blocks:

**The problem with standard attention:**

```
Standard:
  1. Compute S = Q × K^T           → 64×64 matrix (4,096 elements)
  2. Apply mask
  3. Compute P = softmax(S)         → 64×64 matrix (4,096 elements)
  4. Compute O = P × V             → 64×16 matrix

  Peak memory: O(N²) where N = sequence length
  At N=64 this is fine, but at N=1024 it's 1M elements per head
```

**Flash attention approach:**

```
Flash:
  Split Q into blocks of size B_q (e.g., 16)
  Split K, V into blocks of size B_kv (e.g., 16)

  For each Q block:
    Initialize: O = 0, l = 0, m = -inf  (running max for numerical stability)
    For each K, V block:
      S_block = Q_block × K_block^T     → B_q × B_kv (small!)
      Apply causal mask to block
      m_new = max(m, max(S_block))
      P_block = exp(S_block - m_new)
      l_new = exp(m - m_new) * l + sum(P_block)
      O = exp(m - m_new) * O + P_block × V_block
      m = m_new, l = l_new
    O = O / l  (normalize by total softmax denominator)

  Peak memory: O(B_q × B_kv) — constant, not O(N²)
```

**The online softmax trick** is the key insight: we track a running maximum
(`m`) and a running sum of exponentials (`l`). When we see a new block with a
higher maximum, we rescale all previous accumulated values. This gives the exact
same result as standard softmax but without materializing the full matrix.

At N=64, flash attention is not faster than standard attention (the overhead of
the block loop exceeds the savings). We implement it for two reasons:

1. **Learning**: Understanding the algorithm by implementing it
2. **Future-proofing**: When we scale to N=256 or N=1024, flash attention
   becomes essential

The implementation provides both `standard_attention/4` and `flash_attention/4`
with the same interface, so we can benchmark and compare.

### Feed-Forward Network (FFN)

Each decoder block has an FFN after attention:

```
FFN(x) = GELU(x × W1 + b1) × W2 + b2

  W1: {64, 256}    (expand 4x)
  W2: {256, 64}    (compress back)

  GELU activation: smooth approximation of ReLU
  Used in GPT-2/3 and most modern transformers
```

The FFN processes each position independently (no cross-position interaction).
It adds "processing capacity" — the attention layer determines what information
to gather from the sequence, and the FFN processes that gathered information.

### Residual Connections

Every sub-layer (attention, FFN) has a residual connection:

```
output = sublayer(LayerNorm(x)) + x
```

This means gradients can flow directly from the output back to earlier layers
without being attenuated by the sublayer computation. It's what makes deep
networks trainable.

### Output Head

The final layer maps d_model=64 to 40 placement logits:

```
logits = LayerNorm(transformer_output) × W_out + b_out
  W_out: {64, 40}

For inference:
  valid_mask = [1, 1, 0, 1, ...]  (from Board.valid_position? checks)
  logits[invalid] = -infinity
  probs = softmax(logits)
  placement = argmax(probs)  (or sample from top-k for exploration)
```

### Parameter Count Breakdown

```
Token projection:      80 × 64 + 64          =   5,184
Positional encoding:   64 × 64               =   4,096
Piece embeddings:      7 × 8 × 2             =     112
Action embedding:      40 × 8                =     320
Per decoder block:
  LayerNorm (×2):      64 × 2 × 2            =     256
  QKV projection:      64 × 64 × 3 + 64 × 3 =  12,480
  Output projection:   64 × 64 + 64          =   4,160
  FFN W1:              64 × 256 + 256         =  16,640
  FFN W2:              256 × 64 + 64          =  16,448
  Block total:                                =  49,984
2 blocks:                                     =  99,968
Final LayerNorm:       64 × 2                 =     128
Output head:           64 × 40 + 40           =   2,600
─────────────────────────────────────────────────────────
Total:                                        ≈ 112,408
```

## Training Data Pipeline

### Phase 1: Recording Bot-vs-Bot Games

We reuse the existing `BotTrainer.BattleSimulation` infrastructure. The
`GameRecorder` module wraps a headless game simulation and captures every piece
placement with full context:

```elixir
# What GameRecorder captures per placement:
%{
  timestep: 42,                    # sequential placement number
  player_id: "bot-1",
  board: [[0, 0, ...], ...],      # 20×10 binary grid
  current_piece: :T,               # piece being placed
  next_piece: :I,                  # lookahead piece
  pending_garbage: 2,              # garbage rows incoming
  own_max_height: 12,              # tallest column
  opponent_max_height: 8,          # opponent's tallest
  combo_count: 3,                  # consecutive line clears
  lines: 45,                       # total lines cleared
  score: 12400,                    # total score
  opponent_count: 2,               # alive opponents
  placement: %{rotation: 2, column: 4},  # what the bot chose
  outcome: :survived               # did this player win/survive?
}
```

We run hard-mode bots against each other in 4-player battles. Hard bots use the
evolved weights and 2-piece lookahead, so their play is strong and strategically
coherent — exactly what we want TetrisGPT to learn.

**Data volume**: Start with 100 games. Each game has 4 players, each placing
~60-150 pieces. That gives us roughly 24,000-60,000 individual placements.

### Phase 2: Sequence Construction

Raw placements are converted to sliding-window sequences:

```
Player's placement timeline: [p0, p1, p2, ..., p119]

Sliding windows (seq_len=64):
  Window 0: [p0,  p1,  p2,  ..., p63]   → target: [p1,  p2,  ..., p63,  p64]
  Window 1: [p1,  p2,  p3,  ..., p64]   → target: [p2,  p3,  ..., p64,  p65]
  ...
  Window 55: [p55, p56, p57, ..., p118] → target: [p56, p57, ..., p118, p119]
```

For games shorter than 64 placements, we pad the beginning with zeros and use
an attention mask to ignore padded positions.

**Filtering**: We only keep sequences from players who survived past 30
placements. Players eliminated early were making poor decisions — training on
their data would teach bad strategy.

**Data volume after windowing**: 100 games × 4 players × ~57 windows ≈ 22,800
training sequences. Each sequence is {64, 80} floats = 20KB. Total dataset:
~450MB (manageable on disk and in memory).

### Phase 3: Tensor Batching

Sequences are grouped into batches of 32 for training:

```
train_batch:
  input:  {32, 64, 80}    float32  (32 sequences, 64 tokens, 80 features)
  target: {32, 64}         int32    (placement indices)
  mask:   {32, 64}         float32  (1.0 for real positions, 0.0 for padding)
```

Train/validation split: 90/10 (random, but keeping all windows from the same
game in the same split to prevent data leakage).

## Training

### Loss Function

Cross-entropy loss over 40 placement classes, masked to ignore padded positions:

```
loss = -sum(mask * log(probs[target])) / sum(mask)
```

### Optimizer

Adam with weight decay (AdamW):
- Learning rate: 3e-4 (standard for small transformers)
- Weight decay: 1e-4 (light L2 regularization)
- Betas: (0.9, 0.999) (Adam defaults)

### Learning Rate Schedule

Cosine decay with linear warmup:

```
Step 0-100:    linear warmup from 0 to 3e-4
Step 100-end:  cosine decay from 3e-4 to 3e-5 (10x reduction)
```

Warmup prevents early training instability. Cosine decay gives the model time
to refine weights as training progresses.

### Training Loop

```
for epoch 1..50:
  for batch in train_data:
    logits = model(batch.input)
    loss = masked_cross_entropy(logits, batch.target, batch.mask)
    backprop and update params

  evaluate on validation set
  log: train_loss, val_loss, top1_acc, top5_acc

  if epoch % 10 == 0:
    save checkpoint to priv/tetris_gpt/checkpoints/
```

### Success Criteria

| Metric | Random Baseline | Target | What It Means |
|--------|----------------|--------|---------------|
| Top-1 accuracy | 2.5% (1/40) | >30% | Model picks the same move as the bot >30% of the time |
| Top-5 accuracy | 12.5% (5/40) | >60% | Bot's move is in the model's top 5 choices |
| Val loss | ~3.7 (ln 40) | <2.5 | Model is learning, not memorizing |
| Beat easy bot | 0% | >50% | Model is strategically competent |

Top-1 accuracy of 30% might sound low, but many placements are "equally good" —
the bot's choice is somewhat arbitrary among several strong options. Top-5
accuracy is the more meaningful metric.

## Agent Integration: GptBotPlayer

### GenServer Lifecycle

`GptBotPlayer` mirrors the existing `BotPlayer` lifecycle exactly:

```
States: :waiting → :thinking → :executing → :thinking → ...

Events:
  {:game_started, _}        → enter :thinking
  {:game_state, payload}    → buffer state, maybe trigger think
  :think                    → run inference, plan actions
  :execute_action           → send next action to GameRoom
```

### State

```elixir
%{
  room_id: String.t(),
  player_id: String.t(),
  model_params: map(),              # Axon model parameters
  model_state: term(),              # Strategy-specific state
  strategy: module(),               # TetrisGPT.Strategy implementation
  context_buffer: :queue.queue(),   # ring buffer of last 64 states
  phase: :waiting | :thinking | :executing,
  action_queue: list(atom()),
  think_timer: reference() | nil,
  action_timer: reference() | nil
}
```

### Inference Flow

```
1. New piece detected in game_state broadcast
2. Append current state to context_buffer (drop oldest if >64)
3. Encode context_buffer → {1, 64, 80} tensor
4. Call strategy.predict(model_state, tensor) → placement logits
5. Enumerate valid placements via BotStrategy.enumerate_placements/2
6. Mask invalid logits → -infinity
7. Argmax (or top-k sampling) → {rotation, column}
8. BotStrategy.plan_actions/3 → [:rotate, :move_right, :hard_drop, ...]
9. Queue actions, enter :executing, fire actions on timer
```

### Timing

The existing hard bot thinks for 50-100ms. The ~110K param model should infer
in 5-15ms on CPU (with EXLA backend). This leaves headroom for scaling up the
model later.

Action execution uses the same configurable timer as existing bots (50ms per
action for hard difficulty).

## Strategy Behaviour

```elixir
defmodule TetrisGPT.Strategy do
  @type state :: term()
  @type context :: %{
    board: Nx.Tensor.t(),
    current_piece: atom(),
    next_piece: atom(),
    battle_context: map(),
    sequence: list(map())
  }
  @type placement :: %{rotation: 0..3, column: 0..9}

  @callback init(opts :: keyword()) :: state
  @callback predict(state, context) :: {placement, state}
  @callback name() :: String.t()
end
```

**Planned implementations:**

| Module | Architecture | Status |
|--------|-------------|--------|
| `TetrisGPT.Strategies.DecoderOnly` | GPT-style transformer | Build now |
| `TetrisGPT.Strategies.CnnTransformer` | CNN encoder + transformer | Build later |
| `TetrisGPT.Strategies.Heuristic` | Wrapper around existing BotStrategy | Build now (for benchmarking) |

## Module Structure

```
server/lib/tetris_gpt/
  strategy.ex                    # Behaviour definition
  strategies/
    decoder_only.ex              # Transformer strategy (Approach A)
    heuristic.ex                 # BotStrategy wrapper for comparison
  model/
    transformer.ex               # Builds Axon model graph
    attention.ex                 # Multi-head + flash attention (Nx)
    layers.ex                    # LayerNorm, FFN, positional encoding
    tokenizer.ex                 # Game state → tensor encoding
  training/
    game_recorder.ex             # Records bot-vs-bot replays
    data_pipeline.ex             # Replays → batched tensors
    trainer.ex                   # Axon.Loop training orchestration
  gpt_bot_player.ex              # GenServer (mirrors BotPlayer)

server/lib/mix/tasks/
  tetris_gpt.record.ex           # mix tetris_gpt.record --games 100
  tetris_gpt.train.ex            # mix tetris_gpt.train --epochs 50
  tetris_gpt.benchmark.ex        # mix tetris_gpt.benchmark

server/priv/tetris_gpt/
  checkpoints/                   # Saved model parameters
  data/                          # Recorded game tensors
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `nx` | ~> 0.9 | Tensor operations and numerical computing |
| `axon` | ~> 0.7 | Neural network definition and training |
| `exla` | ~> 0.9 | XLA backend — JIT compiles Nx ops to native code |
| `polaris` | ~> 0.1 | Optimizers (Adam) and LR schedulers |

EXLA is the recommended Nx backend. It compiles tensor operations via Google's
XLA compiler to optimized native code, giving 10-100x speedup over the default
BinaryBackend, even on CPU. For our ~110K param model, EXLA makes the
difference between 100ms inference (unusable) and 5-15ms (fast).

## Mix Tasks

### `mix tetris_gpt.record`

```
Usage: mix tetris_gpt.record [options]

Options:
  --games N        Number of 4-player bot battles to record (default: 100)
  --difficulty D   Bot difficulty level: hard | battle (default: hard)
  --output PATH    Output directory (default: priv/tetris_gpt/data/)

Records bot-vs-bot games and saves placement sequences to disk.
```

### `mix tetris_gpt.train`

```
Usage: mix tetris_gpt.train [options]

Options:
  --epochs N       Training epochs (default: 50)
  --batch-size N   Batch size (default: 32)
  --seq-len N      Sequence length (default: 64)
  --lr FLOAT       Learning rate (default: 3e-4)
  --data PATH      Training data directory (default: priv/tetris_gpt/data/)
  --checkpoint P   Resume from checkpoint path

Trains the transformer model on recorded game data.
```

### `mix tetris_gpt.benchmark`

```
Usage: mix tetris_gpt.benchmark [options]

Options:
  --games N          Number of benchmark games (default: 20)
  --checkpoint PATH  Model checkpoint to evaluate
  --opponents DIFF   Opponent difficulty: easy | medium | hard (default: easy)

Runs TetrisGPT against heuristic bots and reports win rates.
```

## Future: CNN + Transformer Hybrid (Approach B)

When we're ready to experiment with the CNN variant, we implement a new
`TetrisGPT.Strategies.CnnTransformer` module:

**Changes from Approach A:**
- Board encoding: instead of flatten → linear, use 2 conv layers (3×3 kernels,
  16 and 32 filters) over the 20×10 grid → spatial features → flatten → project
- The CNN learns spatial patterns (T-spin holes, wells, step structures)
  that a linear projection might miss
- Everything else (transformer layers, training pipeline, agent) stays the same

The Strategy behaviour means we swap one line in the config to switch models.

## Glossary

Terms used throughout this document and the codebase:

| Term | Meaning |
|------|---------|
| **Token** | One timestep's game state encoded as a vector |
| **d_model** | Embedding dimension (64) — size of each token vector |
| **d_k** | Key/query dimension per attention head (16 = d_model / n_heads) |
| **d_ff** | Feed-forward hidden dimension (256 = d_model × 4) |
| **Causal mask** | Prevents attending to future positions |
| **Flash attention** | Memory-efficient attention using tiled computation |
| **Residual connection** | Skip connection: output = f(x) + x |
| **Pre-norm** | LayerNorm before sublayer (not after) |
| **GELU** | Gaussian Error Linear Unit — smooth ReLU variant |
| **Top-k sampling** | Pick randomly from the k highest-probability outputs |
| **Placement** | A (rotation, column) pair describing where to put a piece |
