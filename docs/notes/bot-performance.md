# Bot Performance Notes

Analysis of the Tetris bot's strengths and remaining weaknesses.

## Current state

The Hard bot uses 6 heuristic features with weights evolved via genetic algorithm (see `bot-evolution.md`). It evaluates all placements with pruned 2-piece lookahead (top 5 candidates get full next-piece evaluation). Board analysis is pure Elixir — no ML dependencies.

### What's been done

1. **Evolved weights** via GA — replaced hand-picked values with optimized 6-weight vectors
2. **Added max_height and well_sum** metrics — better discrimination between dangerous board states
3. **2-piece lookahead** in simulation — weights are trained with the same evaluation method used in production
4. **Pruned lookahead** — only top 5 greedy candidates get full next-piece evaluation (~5.7x faster)
5. **Distributed training** — evaluation scales across multiple BEAM nodes via Erlang distribution
6. **Pure Elixir board analysis** — replaced Nx/EXLA tensor operations with direct arithmetic (~100x faster per evaluation)

### Remaining weaknesses

1. **No wall kick placements** — the placement enumerator doesn't attempt SRS wall kicks during enumeration, missing tuck-under and T-spin setups
2. **No strategic awareness** — doesn't build for Tetrises (keeping a column open for I-pieces), set up combos, or plan back-to-back clears
3. **No garbage awareness** — ignores `pending_garbage` in placement decisions
4. **Naive target selection** — Hard mode targets the highest scorer rather than the player closest to dying or the one targeting you
5. **No adaptive weights** — uses the same weights regardless of board height (a defensive set for high boards would help survival)

### Potential improvements (ranked by impact)

1. **Wall kick enumeration** — try each rotation with all 5 SRS kick offsets during placement search. Unlocks an entire class of placements the bot can't see.
2. **Adaptive weights by board height** — two weight sets: defensive (height > 12) and aggressive (height <= 12). Simple to implement.
3. **Row/column transitions** — horizontal and vertical cell-to-empty changes per row/column. Measures jaggedness and buried gaps more precisely than bumpiness alone.
4. **Tetris well building** — reward keeping one column clear while filling others. Enables 4-line clears with I-pieces.
5. **Garbage-aware evaluation** — factor `pending_garbage` count into placement score. Penalize placements that leave the board above row 14 when garbage is incoming.
