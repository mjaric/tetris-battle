# Complete tracing of data flow trough layers

## L0: INPUTS

This comes from tokenizer and is set to the input layer.
At the begginging, when game starts this will be empty and only first timestep will be set. This is context window that model will "see". Tokenizer did normalization for us, so everything should be in range of f32 -1.0...1.0

```
═══════════════════════════════════════════════════
board:          {1, 64, 200}    ← 64 timesteps, each a 200-cell board
current_piece:  {1, 64}         ← 64 timesteps, each a piece index 0-6
next_piece:     {1, 64}         ← 64 timesteps, each a piece index 0-6
battle_context: {1, 64, 8}      ← 64 timesteps, each 8 floats
placement:      {1, 64}         ← 64 timesteps, each a placement index 0-39
```

## L1: Project/embed each input (per-timestep, independent)
```
═══════════════════════════════════════════════════
board           {1, 64, 200} × W_board{200, 48}    = {1, 64, 48}
current_piece   {1, 64}     → Embed[7, 8] lookup   = {1, 64, 8}
next_piece      {1, 64}     → Embed[7, 8] lookup   = {1, 64, 8}
battle_context  {1, 64, 8}  → passthrough          = {1, 64, 8}
placement       {1, 64}     → Embed[40, 8] lookup  = {1, 64, 8}
```

## L2: Concatenate along last axis
So above is concatenanted into single `{1, 64, 80}` matrics 
along last axis. 80 = 48+8+8+8+8

```
                                                      ─────────
Concatenate along last axis                        = {1, 64, 80}
```                                                

STEP 3: Project to d_model
═══════════════════════════════════════════════════
{1, 64, 80} × W_proj{80, 64} = {1, 64, 64}
                                ↑   ↑   ↑
                             batch  │  d_model
                                  seq_len
                                (timesteps)

STEP 4: Add positional encoding
═══════════════════════════════════════════════════
{1, 64, 64} + pos_embed{64, 64} = {1, 64, 64}


STEP 5: Decoder block — THIS IS WHERE THE MASK LIVES
═══════════════════════════════════════════════════

Input: x = {1, 64, 64}

  5a. Q, K, V projections (each timestep independently):
      Q = x × W_q{64, 64} = {1, 64, 64}
      K = x × W_k{64, 64} = {1, 64, 64}
      V = x × W_v{64, 64} = {1, 64, 64}

  5b. Split into 4 heads (reshape):
      Q = {1, 4, 64, 16}    ← 4 heads, each 16-dim
      K = {1, 4, 64, 16}       (64/4 = 16)
      V = {1, 4, 64, 16}

  5c. Attention scores — Q × Kᵀ:
      {1, 4, 64, 16} × {1, 4, 16, 64} = {1, 4, 64, 64}
                                                ↑   ↑
                                          "who asks" × "who answers"
                                          (timestep i)  (timestep j)

  ┌─────────────────────────────────────────────────┐
  │ THIS {64, 64} matrix is where the mask applies. │
  │                                                 │
  │ scores[i][j] = "how much should timestep i      │
  │                 pay attention to timestep j?"    │
  │                                                 │
  │ The mask sets future positions (j > i) to -1e9  │
  │ so they get zero weight after softmax.          │
  └─────────────────────────────────────────────────┘

  5d. Apply mask + softmax:
      scores = scores + mask{64, 64}     ← future blocked
      weights = softmax(scores)          = {1, 4, 64, 64}

  5e. Weighted sum of values:
      {1, 4, 64, 64} × V{1, 4, 64, 16} = {1, 4, 64, 16}

  5f. Concat heads + output projection:
      {1, 4, 64, 16} → reshape → {1, 64, 64}
      × W_o{64, 64} = {1, 64, 64}

  5g. Residual + LayerNorm + FFN + Residual:
      {1, 64, 64} → still {1, 64, 64}


STEP 6: Output head — THIS IS WHERE 40 PLACEMENTS APPEAR
═══════════════════════════════════════════════════
{1, 64, 64} × W_out{64, 40} = {1, 64, 40}
                                  ↑   ↑   ↑
                                batch  │   40 placement
                                  seq_len  probabilities

STEP 7: Softmax over last axis
═══════════════════════════════════════════════════
{1, 64, 40} → softmax → {1, 64, 40}

For inference, we take the LAST timestep's output:
  output[0, 63, :] = 40 probabilities
  argmax → placement index → decode to {rotation, column}
