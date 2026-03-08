# TetrisGPT Architecture Diagram

Visual reference for the full tensor flow through the model.

## Glossary

Terms used throughout this document, explained for someone with no
ML background:

**Tensor** — A multi-dimensional array of numbers. A 1D tensor is a
list `[1, 2, 3]`. A 2D tensor is a table (matrix). A 3D tensor is a
stack of tables. Tensors are how neural networks represent all data.

**Shape notation `{B, 64, 200}`** — Describes the dimensions of a
tensor. This one has 3 axes: axis 0 has `B` elements, axis 1 has 64,
axis 2 has 200. Total numbers stored: `B × 64 × 200`.

**B (batch size)** — How many independent examples the model
processes in parallel. During training, we feed 32 game sequences at
once (`B=32`) because GPUs are fast at parallel math — processing 32
sequences takes almost the same time as 1. During inference (the bot
playing), `B=1` because we're only deciding one move at a time. The
model architecture is the same regardless of B; it just processes
more data in parallel.

**d_model (dimension of the model)** — The width of the internal
representation vector. Every timestep flowing
through the transformer is represented as a vector of `d_model`
numbers. We chose `d_model=64`. This is like the "vocabulary" the
model uses internally to describe each game state, 64 numbers that
encode everything about that moment. All layers inside the
transformer operate on this width.

**Dense (Linear) layer** — The simplest neural network operation:
multiply input by a weight matrix, add a bias vector. If input is
`{200}` and weights are `{200, 48}`, output is `{48}`. The weight
values are learned during training.

**Embedding** — A lookup table that maps integer indices to learned
vectors. For example, piece index 2 (`:T`) maps to 8 learned
numbers like `[0.12, -0.34, 0.56, ...]`. Unlike one-hot encoding
(which just puts a 1 in one position), embeddings let the model
learn relationships between categories.

**Softmax** — Converts a list of raw numbers (any range) into
probabilities (all positive, sum to 1.0). `[2.0, 1.0, 0.1]` →
`[0.66, 0.24, 0.10]`. Used to create attention weights and output
probabilities.

**Residual connection** — Adding the input of a layer back to its
output: `output = layer(x) + x`. Prevents information from being
lost as data flows through many layers. Without residuals, deep
networks struggle to train because gradients vanish.

**LayerNorm** — Normalizes a vector so its values have mean=0 and
standard deviation=1, then scales by learned parameters. Keeps
numbers from growing too large or too small as data flows through
the network. Applied before each major operation (pre-norm style).

**GELU** — An activation function (like a gate). It lets large
positive values through unchanged, blocks large negative values,
and lets small negative values through slightly. Standard for
transformers. Without nonlinear activations, stacking linear layers
would just be one big linear layer — no complex patterns could be
learned.

---

## Architecture Parameters

All architecture parameters are defined in
`Transformer.default_config()`. Here is each parameter, its value,
and why:

```elixir
%{
  d_model: 64,          # internal representation width
  n_heads: 4,           # parallel attention patterns
  d_ff: 256,            # feed-forward network hidden width
  n_layers: 2,          # number of decoder blocks
  max_seq_len: 64,      # context window (timesteps)
  num_piece_types: 7,   # I, O, T, S, Z, J, L
  num_placements: 40,   # 4 rotations × 10 columns
  piece_embed_dim: 8,   # embedding size for piece types
  dropout: 0.1,         # regularization rate
  board_dim: 200,       # 20 rows × 10 columns
  battle_ctx_dim: 8     # normalized battle features
}
```

### Parameter reasoning

**`d_model: 64`** — The width of the vector representing each
timestep inside the transformer. Larger = more expressive but more
parameters and slower. GPT-2 uses 768, GPT-3 uses 12288. We use 64
because: (a) our problem domain is simpler than natural language,
(b) we want inference fast enough for real-time play (50ms tick),
(c) we're starting small to experiment. This is the single most
important parameter for model capacity.

**`n_heads: 4`** — How many parallel attention patterns to learn.
Each head gets `d_model / n_heads = 64/4 = 16` dimensions to work
with (`d_k=16`). More heads = more diverse attention patterns but
each head has fewer dimensions. 4 heads is standard for small
models. One head might learn "look at recent placements," another
"look at moves when garbage arrived."

**`d_ff: 256`** — Hidden width of the feed-forward network inside
each decoder block. Convention is `4 × d_model = 4 × 64 = 256`.
The FFN expands to this width, applies GELU, then compresses back
to `d_model`. The expansion gives the network temporary "scratch
space" for computation.

**`n_layers: 2`** — How many decoder blocks are stacked. More layers
= deeper reasoning but more parameters and slower. GPT-2 has 12,
GPT-3 has 96. We use 2 because our problem doesn't need deep
reasoning chains — Tetris strategy is more about pattern recognition
than multi-step logic. We can increase this later if 2 layers
underperform.

**`max_seq_len: 64`** — How many past timesteps (piece placements)
the model can see. This is the "memory" — 64 moves back. We chose
this during brainstorming as "medium context." Too short and the
model can't remember strategies; too long and training is slow
(attention is O(n^2) in sequence length). 64 covers several Tetris
"phases" (build, clear, garbage response).

**`num_piece_types: 7`** — Fixed by Tetris rules: I, O, T, S, Z,
J, L. Not a design choice.

**`num_placements: 40`** — 4 rotations × 10 columns = 40 possible
placements per piece. This is the output size — the model chooses
one of 40 options. Not all are valid for every piece (masked during
inference). Fixed by game geometry.

**`piece_embed_dim: 8`** — Dimension of piece type and placement
embeddings. Must be small relative to `d_model` since we concatenate
4 embeddings (2 pieces + battle context + placement = 8+8+8+8=32)
plus the board projection (48), totaling 80 before the token
projection squeezes to 64. The value 8 gives enough room for the
model to learn meaningful piece relationships without dominating the
token.

**`dropout: 0.1`** — During training, randomly zeroes 10% of values
in certain layers. This prevents overfitting (memorizing training
data instead of learning general patterns). Set to 0.0 in tests for
determinism. Standard value for small models.

**`board_dim: 200`** — 20 rows × 10 columns = 200. Fixed by Tetris
board size.

**`battle_ctx_dim: 8`** — 8 normalized features describing the
multiplayer situation (garbage pending, heights, combo, etc.).
Defined by the tokenizer.

### Derived values (computed from the above)

| Derived | Value | Formula |
|---------|-------|---------|
| `d_k` (per-head dimension) | 16 | `d_model / n_heads` = 64/4 |
| `board_proj_dim` | 48 | `d_model - 2*piece_embed - battle_ctx - piece_embed` |
| Token width before projection | 80 | 48 + 8 + 8 + 8 + 8 |
| Attention matrix size | 64x64 | `max_seq_len * max_seq_len` |
| Total parameters | ~121K | see table below |

---

## Full Network Diagram

Every `{B, 64, ...}` tensor has 3 axes:
- Axis 0: **B** — batch (how many games in parallel)
- Axis 1: **64** — time (which timestep, 0=oldest, 63=current)
- Axis 2: **varies** — features (what the numbers represent)

```
                          INPUTS (from Tokenizer)
 ┌──────────────────┬───────────────┬──────────────┬─────────────────┬──────────────┐
 │ board            │ current_piece │ next_piece   │ battle_context  │ placement    │
 │ {B, 64, 200}     │ {B, 64}       │ {B, 64}      │ {B, 64, 8}      │ {B, 64}      │
 │ float32          │ int32         │ int32        │ float32         │ int32        │
 └────────┬─────────┴───────┬───────┴──────┬───────┴────────┬────────┴──────┬───────┘
          │                 │              │                │               │
          ▼                 ▼              ▼                │               ▼
 ┌─────────────────┐ ┌───────────┐ ┌───────────┐          │        ┌───────────┐
 │  Dense (Linear) │ │ Embedding │ │ Embedding │          │        │ Embedding │
 │  W: {200, 48}   │ │ [7 x 8]   │ │ [7 x 8]   │          │        │ [40 x 8]  │
 │  b: {48}        │ │           │ │           │          │        │           │
 └────────┬────────┘ └─────┬─────┘ └─────┬─────┘          │        └─────┬─────┘
          │                │             │                │              │
          ▼                ▼             ▼                ▼              ▼
    {B, 64, 48}      {B, 64, 8}   {B, 64, 8}      {B, 64, 8}    {B, 64, 8}
          │                │             │                │              │
          └────────┬───────┴─────┬───────┴────────┬───────┴──────┬──────┘
                   │             │                │              │
                   ▼             ▼                ▼              ▼
              ┌──────────────────────────────────────────────────────┐
              │               Concatenate (axis=2)                  │
              │          48 + 8 + 8 + 8 + 8 = 80                   │
              └──────────────────────┬──────────────────────────────┘
                                     │
                                     ▼
                               {B, 64, 80}
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │    Dense (Linear)    │
                          │    W: {80, 64}       │
                          │    b: {64}           │
                          │   "token_projection" │
                          └──────────┬──────────┘
                                     │
                                     ▼
                               {B, 64, 64}
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │      + Add          │
                          │  pos_embed{64, 64}  │
                          │ "positional_encoding"│
                          └──────────┬──────────┘
                                     │
                                     ▼
                               {B, 64, 64}
                                     │
               ┌─────────────────────┴─────────────────────┐
               │         DECODER BLOCK 0                    │
               │                                            │
               │  ┌──────────────┐                         │
               │  │  LayerNorm   │                         │
               │  └──────┬───────┘                         │
               │         ▼                                  │
               │  ┌──────────────────────────────────────┐ │
               │  │      Multi-Head Attention            │ │
               │  │      (4 heads, d_k=16)               │ │
               │  │                                      │ │
               │  │  Q = x*W_q  K = x*W_k  V = x*W_v   │ │
               │  │  {B,64,64}  {B,64,64}  {B,64,64}    │ │
               │  │       │          │          │        │ │
               │  │       ▼          ▼          ▼        │ │
               │  │  {B,4,64,16} {B,4,64,16} {B,4,64,16}│ │
               │  │       │          │                   │ │
               │  │       ▼          ▼                   │ │
               │  │    Q * Kt / sqrt(16)                 │ │
               │  │  = {B, 4, 64, 64}  <- attention score│ │
               │  │       │                              │ │
               │  │       ▼                              │ │
               │  │  + causal_mask {64, 64}              │ │
               │  │  ┌──────────────────────────┐        │ │
               │  │  │ 0  -∞  -∞  -∞ ... -∞    │        │ │
               │  │  │ 0   0  -∞  -∞ ... -∞    │        │ │
               │  │  │ 0   0   0  -∞ ... -∞    │        │ │
               │  │  │ :   :   :   :  .    :    │        │ │
               │  │  │ 0   0   0   0 ...  0    │        │ │
               │  │  └──────────────────────────┘        │ │
               │  │       │                              │ │
               │  │       ▼                              │ │
               │  │    softmax -> weights {B,4,64,64}    │ │
               │  │       │                              │ │
               │  │       ▼                              │ │
               │  │  weights * V = {B, 4, 64, 16}       │ │
               │  │       │                              │ │
               │  │       ▼  concat heads + W_o          │ │
               │  │    {B, 64, 64}                       │ │
               │  └──────────────┬───────────────────────┘ │
               │                 │                          │
               │         ┌───────┴───────┐                 │
               │         │   + Residual  │<-- input        │
               │         └───────┬───────┘                 │
               │                 │                          │
               │         ┌───────┴───────┐                 │
               │         │  LayerNorm    │                 │
               │         └───────┬───────┘                 │
               │                 │                          │
               │         ┌───────┴───────┐                 │
               │         │  FFN (GELU)   │                 │
               │         │ Dense{64,256} │                 │
               │         │    GELU       │                 │
               │         │ Dense{256,64} │                 │
               │         └───────┬───────┘                 │
               │                 │                          │
               │         ┌───────┴───────┐                 │
               │         │   + Residual  │<-- after attn   │
               │         └───────┬───────┘                 │
               │                 │                          │
               │           {B, 64, 64}                      │
               └─────────────────┬─────────────────────────┘
                                 │
               ┌─────────────────┴─────────────────────┐
               │         DECODER BLOCK 1                │
               │         (same structure as block 0)    │
               │              ...                       │
               │           {B, 64, 64}                  │
               └─────────────────┬─────────────────────┘
                                 │
                                 ▼
                      ┌─────────────────────┐
                      │     LayerNorm       │
                      │    "final_norm"     │
                      └──────────┬──────────┘
                                 │
                                 ▼
                           {B, 64, 64}
                                 │
                                 ▼
                      ┌─────────────────────┐
                      │   Dense (Linear)    │
                      │   W: {64, 40}       │
                      │   b: {40}           │
                      │   "output_head"     │
                      └──────────┬──────────┘
                                 │
                                 ▼
                           {B, 64, 40}
                                 │
                                 ▼
                      ┌─────────────────────┐
                      │   Softmax (axis=2)  │
                      └──────────┬──────────┘
                                 │
                                 ▼
                           {B, 64, 40}
                      40 placement probabilities
                       per timestep position

                    For inference, take last position:
                      output[0, 63, :] -> 40 probs
                      argmax -> placement index
                      decode -> {rotation, column}
```

---

## Layer-by-Layer Explanation

### Input Layer: Tokenizer Output

The tokenizer provides raw game data as separate tensors. No
dimensionality reduction happens here — the model learns its own
projections.

| Tensor | Shape | Type | Content |
|--------|-------|------|---------|
| `board` | `{B, 64, 200}` | f32 | 20x10 binary grid per timestep. Each of 64 timesteps has 200 floats (0.0=empty cell, 1.0=filled). |
| `current_piece` | `{B, 64}` | s32 | Piece type index 0-6 (I=0, O=1, T=2, S=3, Z=4, J=5, L=6) for each timestep. |
| `next_piece` | `{B, 64}` | s32 | Same encoding, the piece coming after the current one. |
| `battle_context` | `{B, 64, 8}` | f32 | 8 normalized battle features per timestep (garbage pending, heights, combo, etc.). |
| `placement` | `{B, 64}` | s32 | Placement index 0-39. Encodes `rotation * 10 + column`. |
| `mask` | `{B, 64}` | f32 | 1.0 for real timesteps, 0.0 for padding positions (when game has fewer than 64 moves). |

### Board Projection: Dense(200, 48)

```
board{B, 64, 200} x W_board{200, 48} + bias{48} = {B, 64, 48}
```

**What it does:** Takes each timestep's 200-number board
representation and compresses it to 48 numbers.

**How:** Matrix multiplication. Each of the 48 output features is a
weighted sum of all 200 input cells. The 200x48 = 9,600 weights are
learned during training — the model discovers which combinations of
cells matter (e.g., "column 5 height" might become one feature).

**Why 48:** We need the board projection + all embeddings to add up
to a reasonable token width. 48 + 8 + 8 + 8 + 8 = 80 features
before the token projection. 48 gives the board the largest share
(60%) since it's the most information-dense input.

**Why compress at all:** If we used all 200 board features directly,
they'd dominate the token (200 out of 264 total features = 76%).
The model would focus almost entirely on raw cell positions and
ignore the pieces, placements, and battle context.

### Piece Embeddings: Embedding(7, 8)

```
current_piece{B, 64} -> lookup table [7 x 8] -> {B, 64, 8}
next_piece{B, 64}    -> lookup table [7 x 8] -> {B, 64, 8}
```

**What it does:** Converts piece type integers (0-6) into
8-dimensional learned vectors.

**How:** A table of 7 rows x 8 columns. Piece index 2 -> row 2 of
the table -> 8 numbers. No math, just a lookup. The table values are
learned during training.

**Why not just use the integer:** If we fed the integer 2 directly,
the model would think T-piece (2) is "between" O-piece (1) and
S-piece (3), and that L-piece (6) is "3x more" than T-piece (2).
These relationships are meaningless. An embedding lets the model
learn that S and Z are similar (both awkward), I is unique (only
4-wide piece), etc.

**Why 8 dimensions:** Large enough to capture piece relationships,
small enough not to dominate the token. With only 7 piece types, 8
dimensions is more than enough — you could theoretically represent
7 categories perfectly in 7 dims, but 8 gives the model room to
learn richer representations.

**Two separate tables:** The model can learn different
representations for "piece I'm placing now" vs "piece coming next."
The current piece matters for immediate tactics; the next piece
matters for planning ahead.

### Battle Context: Passthrough

```
battle_context{B, 64, 8} -> {B, 64, 8}  (no transformation)
```

**What it does:** Nothing — passes through unchanged.

**Why no projection:** Already compact at 8 numbers, all pre-normalized
to roughly [0, 1] by the tokenizer. No compression needed.

### Placement Embedding: Embedding(40, 8)

```
placement{B, 64} -> lookup table [40 x 8] -> {B, 64, 8}
```

**What it does:** Converts the placement index (0-39) at each past
timestep into a learned 8-dimensional vector.

**Why it matters:** The placement tells the model what action was
taken at each past timestep. Without it, the model would see 64
board states but not know what moves connected them.

**During inference:** The current timestep's placement is set to 0
(dummy value) because we haven't decided yet — the whole point of
running the model is to choose this placement. The output head
predicts it.

### Concatenation

```
concat([board_proj, cur_embed, nxt_embed, battle_ctx, act_embed], axis=2)
  {B,64,48} ++ {B,64,8} ++ {B,64,8} ++ {B,64,8} ++ {B,64,8}
= {B, 64, 80}
```

**What it does:** Joins all per-timestep features side by side into
one 80-number vector per timestep.

**Visually for one timestep:**
```
[board: 48 numbers | cur_piece: 8 | next_piece: 8 | battle: 8 | placement: 8]
 <---- 80 numbers total ---->
```

### Token Projection: Dense(80, 64)

```
token{B, 64, 80} x W_proj{80, 64} + bias{64} = {B, 64, 64}
```

**What it does:** Compresses the 80-feature token to the
transformer's working width of 64 (`d_model`).

**Why not keep 80:** The transformer's internal layers all operate at
`d_model` width. A consistent width simplifies the architecture
(residual connections require matching dimensions) and forces the
model to learn a compact representation.

### Positional Encoding: Learned

```
{B, 64, 64} + pos_embed{64, 64} = {B, 64, 64}
```

**What it does:** Adds a unique "timestamp" to each position in the
sequence, so the model knows the order of events.

**Why it's needed:** Without positional encoding, the model treats
the 64 timesteps as an unordered set — it can't tell if a board
state was 2 moves ago or 50 moves ago. The positional embedding
gives each position a unique 64-number fingerprint.

**How:** `pos_embed` is a learnable matrix with one row per position
(64 rows x 64 columns). Position 0 gets `pos_embed[0]` added to it,
position 1 gets `pos_embed[1]`, etc. The values are learned during
training — the model discovers its own representation of "recency"
and "temporal distance."

### Decoder Block (x2)

Two identical blocks stacked. Each has two sub-layers.

#### Sub-layer 1: Multi-Head Self-Attention

This is the core mechanism that lets each timestep "look at" other
timesteps and gather relevant information.

```
1. LayerNorm(input)              -> {B, 64, 64}

2. Linear projections (per timestep, independently):
   Q = normed x W_q{64, 64}     -> {B, 64, 64}
   K = normed x W_k{64, 64}     -> {B, 64, 64}
   V = normed x W_v{64, 64}     -> {B, 64, 64}

3. Split into 4 heads (reshape + transpose):
   Q -> {B, 4, 64, 16}    (4 heads, 16 dims each)
   K -> {B, 4, 64, 16}
   V -> {B, 4, 64, 16}

4. Attention scores:
   scores = Q * Kt / sqrt(16)   -> {B, 4, 64, 64}
                                        ^  ^  ^
                                      heads |  |
                                      "who asks" (row)
                                           "who answers" (column)

5. Causal mask (added to scores):
   scores + mask{64, 64}         -> {B, 4, 64, 64}
   (future positions -> -1e9 -> become 0 after softmax)

6. Softmax (per row):
   weights = softmax(scores)     -> {B, 4, 64, 64}
   (each row sums to 1.0)

7. Weighted sum of values:
   output = weights * V          -> {B, 4, 64, 16}

8. Concat heads + output projection:
   reshape -> {B, 64, 64}
   x W_o{64, 64}                -> {B, 64, 64}

9. Residual: input + attn_out   -> {B, 64, 64}
```

**Q, K, V explained with an analogy:**

Imagine a library where each timestep is a person:
- **Q (Query)** = "What information am I looking for?"
- **K (Key)** = "What information do I have to offer?"
- **V (Value)** = "Here's my actual information."

Step 4 computes `Q * Kt` — this asks: "Does my query match your
key?" If timestep 30's query matches timestep 12's key (high dot
product), timestep 30 will pay a lot of attention to timestep 12's
value. The `/ sqrt(16)` scaling prevents scores from becoming too
large (which would make softmax outputs too extreme — nearly 0 or 1).

**Multi-head:** 4 heads run this in parallel on different 16-dim
slices. One head might learn to match "recent moves" (queries look
for temporal proximity). Another might match "moves where garbage
arrived" (queries look for battle context similarity). After
attention, the 4 heads are concatenated back to 64 dims.

**Causal mask:** The 64x64 score matrix has row i = "timestep i is
asking" and column j = "about timestep j." The mask sets all j > i
to negative infinity, so after softmax those weights become 0.
Timestep 30 cannot see timesteps 31-63. This enforces the time
ordering of the game.

#### Sub-layer 2: Feed-Forward Network (FFN)

```
1. LayerNorm(input)              -> {B, 64, 64}
2. Dense(64, 256) + GELU        -> {B, 64, 256}
3. Dense(256, 64)                -> {B, 64, 64}
4. Residual: input + ffn_out    -> {B, 64, 64}
```

**What it does:** After attention has gathered information from other
timesteps, the FFN processes each timestep independently. It expands
to 4x width (256), applies a nonlinear activation (GELU), then
compresses back to 64.

**Why expand then compress:** The expansion gives the model temporary
"scratch space" — 256 features to compute intermediate results —
before condensing back to 64. Think of it like spreading out your
work on a large desk, then filing the results in a compact folder.

**Why independent per timestep:** Attention handles cross-timestep
relationships. The FFN handles "given what I now know about this
timestep (after attention mixed in info from other timesteps),
compute useful features." Each of the 64 positions goes through
the exact same FFN with the same weights.

### Final LayerNorm

```
LayerNorm(input)                 -> {B, 64, 64}
```

Normalizes the output of the last decoder block before the
classification head. Ensures activations are in a stable range
for the output projection.

### Output Head: Dense(64, 40) + Softmax

```
dense: {B, 64, 64} x W_out{64, 40} + bias{40} = {B, 64, 40}
softmax: {B, 64, 40} -> {B, 64, 40}  (each of 40 values -> probability)
```

**What it does:** Projects each timestep's 64-dim representation to
40 numbers — one per possible placement (4 rotations x 10 columns).
Softmax converts these to probabilities that sum to 1.0.

**During training:** Every timestep's output is compared against the
actual placement that was chosen in the recorded game. The loss
function measures how wrong the model was, and backpropagation
adjusts all weights to be less wrong next time.

**During inference (bot playing):** We only care about the last
position (index 63 — the current move). `output[0, 63, :]` gives 40
probabilities. Invalid placements (piece can't physically fit) are
masked to 0. The highest remaining probability is chosen.

---

## Parameter Count

Every weight and bias in the network is a "parameter" — a number
learned during training. More parameters = more capacity to learn
patterns, but also more data needed and slower to train/run.

| Component | Params | Calculation |
|-----------|--------|-------------|
| Board projection W + b | 9,648 | 200x48 + 48 |
| Current piece embedding | 56 | 7x8 |
| Next piece embedding | 56 | 7x8 |
| Placement embedding | 320 | 40x8 |
| Token projection W + b | 5,184 | 80x64 + 64 |
| Positional encoding | 4,096 | 64x64 |
| Block 0: W_q, W_k, W_v, W_o | 16,384 | 4 x (64x64) |
| Block 0: 2x LayerNorm (gamma + beta) | 256 | 2 x (64 + 64) |
| Block 0: FFN W + b | 33,024 | (64x256 + 256) + (256x64 + 64) |
| Block 1: (same as block 0) | 49,664 | same |
| Final LayerNorm (gamma + beta) | 128 | 64 + 64 |
| Output head W + b | 2,600 | 64x40 + 40 |
| **Total** | **~121K** | |

For context: GPT-2 Small has 124M parameters (1,000x more). Our
model is intentionally tiny for fast experimentation on a laptop.

---

## Inference Path (How the Bot Decides)

```
Game state arrives from GameRoom
(board, current piece, next piece, battle context)
        |
        v
Append to history buffer (keeps last 64 timesteps)
        |
        v
Tokenizer.encode_structured_sequence(history, seq_len: 64)
  -> %{"board" => {64, 200}, "current_piece" => {64}, ...}
        |
        v
Add batch dimension (axis 0) to each tensor
  -> %{"board" => {1, 64, 200}, "current_piece" => {1, 64}, ...}
        |
        v
predict_fn.(params, input_map)
  -> runs the full network diagram above
        |
        v
output = {1, 64, 40}  (40 probabilities per timestep)
        |
        v
Take last position: output[0, 63, :] -> 40 probabilities
  (only the current move matters for inference)
        |
        v
Mask invalid placements
  (e.g., I-piece rotated sideways can't fit at column 8)
  -> set those probabilities to 0
        |
        v
argmax -> highest probability -> placement index (e.g., 15)
        |
        v
decode_placement(15) -> %{rotation: 1, column: 5}
        |
        v
plan_actions(spawn_x=3, rotation=1, column=5)
  -> [:rotate_cw, :move_left, :move_left, :hard_drop]
        |
        v
Submit actions to GameRoom one by one (50ms intervals)
```
