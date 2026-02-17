# Bot fitnes notes


# Initial run
Observation notes about imrpovements on bot gameplay.

For first simualtion, I used defaults
```
Population:   50
Generations:  100
Games/genome: 10
Concurrency:  14
Total games:  50000

Gen   1 | Best:   25.8 lines | Avg:   15.6 | W: h=0.22 o=0.25 b=0.20 l=0.33
Gen   2 | Best:   28.3 lines | Avg:   19.7 | W: h=0.20 o=0.31 b=0.20 l=0.29
Gen   3 | Best:   30.0 lines | Avg:   19.6 | W: h=0.50 o=0.03 b=0.21 l=0.26
Gen   4 | Best:   30.2 lines | Avg:   21.5 | W: h=0.45 o=0.23 b=0.30 l=0.02
Gen   5 | Best:   34.7 lines | Avg:   21.3 | W: h=0.42 o=0.14 b=0.27 l=0.17
Gen   6 | Best:   29.5 lines | Avg:   20.8 | W: h=0.54 o=0.13 b=0.33 l=0.00
Gen   7 | Best:   35.0 lines | Avg:   21.1 | W: h=0.53 o=0.03 b=0.18 l=0.26
Gen   8 | Best:   30.1 lines | Avg:   20.8 | W: h=0.32 o=0.18 b=0.21 l=0.28
Gen   9 | Best:   27.3 lines | Avg:   21.9 | W: h=0.49 o=0.07 b=0.27 l=0.17
Gen  10 | Best:   30.9 lines | Avg:   21.9 | W: h=0.44 o=0.19 b=0.24 l=0.13
Gen  11 | Best:   34.3 lines | Avg:   22.3 | W: h=0.44 o=0.19 b=0.24 l=0.13
Gen  12 | Best:   29.6 lines | Avg:   21.9 | W: h=0.41 o=0.21 b=0.20 l=0.19
Gen  13 | Best:   30.6 lines | Avg:   21.7 | W: h=0.42 o=0.25 b=0.22 l=0.12
Gen  14 | Best:   30.5 lines | Avg:   21.9 | W: h=0.53 o=0.00 b=0.20 l=0.26
Gen  15 | Best:   26.9 lines | Avg:   20.1 | W: h=0.39 o=0.19 b=0.16 l=0.25
Gen  16 | Best:   31.1 lines | Avg:   22.0 | W: h=0.48 o=0.10 b=0.20 l=0.22
Gen  17 | Best:   31.0 lines | Avg:   22.6 | W: h=0.52 o=0.03 b=0.20 l=0.25
Gen  18 | Best:   30.3 lines | Avg:   21.8 | W: h=0.57 o=0.00 b=0.23 l=0.20
Gen  19 | Best:   29.0 lines | Avg:   22.0 | W: h=0.77 o=0.06 b=0.18 l=0.00
Gen  20 | Best:   34.2 lines | Avg:   21.7 | W: h=0.44 o=0.19 b=0.18 l=0.18
```

Output clearly shows that there is some progres 15.6 -> 22.0 steady climbing but then it keeps crossing 21.5 down/up. 

The problem: Best fitness bounces wildly (34.7 -> 29.5 -> 35.0 -> 30.1 -> 27.3). With only 10 games per genome, a genome that gets lucky piece sequences looks "best" even if it's mediocre. The GA then selects lucky genomes instead of genuinely good ones.
  
To fix this, we should increase `games_per_genome`. More games per evaluation = more stable fitness = the GA can actually tell good weights from lucky ones.

next run 
```shell
 mix bot.evolve --games 30
 ```
 
Going from 10 to 30 games triples the runtime but dramatically reduces noise. Expecting to see some imrovements:
- Best fitness stop bouncing as much between generations
- Weights converge faster instead of drifting randomly
- Clearer upward trend in both best and average

The weights are also not converging yet. Height swings between 0.20 and 0.54 across generations. That's another symptom of the same noise problem. With 30 games the GA can reliably distinguish a 0.45 height weight from a 0.30 one.

--- 

## Run 02

Still not getting better results, 

```
Population:   50
Generations:  100
Games/genome: 30
Concurrency:  14
Total games:  150000

Gen   1 | Best:   25.6 lines | Avg:   17.4 | W: h=0.38 o=0.17 b=0.21 l=0.25
Gen   2 | Best:   25.6 lines | Avg:   19.5 | W: h=0.30 o=0.28 b=0.23 l=0.20
Gen   3 | Best:   25.0 lines | Avg:   20.2 | W: h=0.36 o=0.24 b=0.25 l=0.14
Gen   4 | Best:   27.3 lines | Avg:   22.0 | W: h=0.29 o=0.34 b=0.30 l=0.07
Gen   5 | Best:   28.0 lines | Avg:   21.7 | W: h=0.23 o=0.33 b=0.22 l=0.22
Gen   6 | Best:   26.2 lines | Avg:   21.4 | W: h=0.37 o=0.16 b=0.24 l=0.23
Gen   7 | Best:   26.8 lines | Avg:   21.3 | W: h=0.26 o=0.26 b=0.25 l=0.22
Gen   8 | Best:   26.4 lines | Avg:   21.1 | W: h=0.27 o=0.27 b=0.23 l=0.23
Gen   9 | Best:   27.9 lines | Avg:   21.8 | W: h=0.27 o=0.29 b=0.26 l=0.19
Gen  10 | Best:   26.8 lines | Avg:   21.5 | W: h=0.24 o=0.28 b=0.24 l=0.24
Gen  11 | Best:   26.8 lines | Avg:   21.2 | W: h=0.27 o=0.32 b=0.24 l=0.16
Gen  12 | Best:   26.6 lines | Avg:   21.5 | W: h=0.26 o=0.34 b=0.25 l=0.15
Gen  13 | Best:   27.2 lines | Avg:   22.4 | W: h=0.20 o=0.31 b=0.25 l=0.24
```

It improves in first few Gens, but then stays at same level further.

Here's what is nex to change:

Lookahead in simulation. This should pick_best now scores each placement by current_score + best_next_score, matching what the real Hard bot does. This is the biggest lever, the bot should then considers how the next piece fits after each placement.

Two new heuristic features:
- max_height - penalizes tall stacks (keeps the board low)
- well_sum - penalizes deep wells between columns (reduces wasted space)

6-weight genome - the GA should evolve all 6 weights. Easy/Medium should have the new weights set to 0.0 (no behavior change for them).

**Rationale**
Lookahead in simulation — This fixed a mismatch. The real bot (`BotStrategy.best_placement` for `:hard`) already uses 2-piece lookahead — it considers how the next piece fits after each candidate placement. But the simulation was evaluating only the current piece. So the GA was optimizing weights for blind, single-piece play, then those weights were used with lookahead in the actual game. That's like training a chess player to think one move ahead, then asking them to think two moves ahead with the same strategy. The weights need to be optimized for the same evaluation method they'll actually be used with.

Two new features (`max_height`, `well_sum`) — This one I'm less sure was the right call at this stage. The original 4 features can't distinguish certain board states. For example, `aggregate_height` sums all columns — it treats "9 columns at height 1, one at height 11" the same as "10 columns at height 2", even though the first is far more dangerous. max_height catches that. Similarly, well_sum penalizes deep gaps between tall columns that waste space. But adding features also expands the search space from 4 dimensions to 6, which makes the GA's job harder. It might have been better to first verify that lookahead alone was sufficient to reach 100 lines, then add features only if needed.

The tradeoff for both: each simulated game is roughly 100x slower because every move now evaluates ~100 current placements × ~100 next-piece placements. That's why the tests went from 12 seconds to 7 minutes.

---

## Performance Optimization

The Nx/EXLA tensor library was catastrophically wrong for this workload. The board is 20x10 = 200 cells. EXLA is designed for neural networks with millions of parameters. Each call to `BoardAnalysis.evaluate` was:

1. Converting a 200-cell list to an Nx tensor (allocation overhead)
2. JIT-compiling 6 separate `defn` functions through EXLA (massive per-call overhead)
3. Converting 6 tensor results back to Elixir numbers

With lookahead, this happens ~1000 times per move, ~200,000 times per game, and ~100 million times per generation.

**Changes made:**

1. Replaced `BoardAnalysis` with pure Elixir — single top-to-bottom pass using Erlang tuples for O(1) cell access. No tensors, no JIT.
2. Added pruned lookahead — instead of evaluating all ~34 placements with full next-piece lookahead (~1156 evals/move), score greedily first, then only do lookahead on top 5 (~204 evals/move). 5.7x fewer evaluations.
3. Removed Nx and EXLA dependencies entirely — nothing in the project used them after the rewrite.

**Results:**

| Metric | Before (Nx/EXLA) | After (Pure Elixir) |
|--------|-------------------|--------------------:|
| Full test suite | 96 seconds | 0.9 seconds |
| Evolution test | 61 seconds | 86 milliseconds |
| Board analysis tests | ~3-5 seconds | 0.02 seconds |

Combined speedup for `mix bot.evolve`: estimated 500-1000x faster per generation.
