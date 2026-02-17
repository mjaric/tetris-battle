# Battle-Aware Bot Design

## Problem

The current hard bot plays excellent solo Tetris but loses multiplayer battles because it ignores incoming garbage, opponent board states, and strategic line-clearing. It needs environmental awareness to survive garbage pressure and eliminate opponents.

## Solution

New `:battle` difficulty level using an extended 12-weight genome. The bot scores placements using existing board-quality metrics plus 6 battle-context terms. Weights are evolved via a GA that simulates 4-player battles.

## Battle Context

Passed to the scoring function each time the bot evaluates placements:

```elixir
%{
  pending_garbage_count: integer(),
  own_max_height: integer(),
  opponent_max_heights: [integer()],
  opponent_count: integer(),
  leading_opponent_score: integer()
}
```

Extracted from the game state payload that `BotPlayer` already receives.

## Extended Genome (12 weights)

Existing 6 (unchanged):

| Weight | Role |
|--------|------|
| `height` | Penalize aggregate column height |
| `holes` | Penalize buried holes |
| `bumpiness` | Penalize uneven surface |
| `lines` | Reward line clears |
| `max_height` | Penalize tallest column |
| `wells` | Penalize deep wells |

New 6 (battle-specific):

| Weight | Role |
|--------|------|
| `garbage_incoming` | Penalize risky placements when garbage is queued |
| `garbage_send` | Bonus for clearing 2+ lines (sends garbage to target) |
| `tetris_bonus` | Extra bonus for 4-line clears (sends 3 garbage) |
| `opponent_danger` | Bonus when opponents' boards are tall (press advantage) |
| `survival` | Penalize own high board more aggressively |
| `line_efficiency` | Prefer multi-line clears over singles |

## Scoring Formula

```
score = base_score(existing 6 weights x board metrics)
      - garbage_incoming x pending_garbage_count x own_max_height_ratio
      + garbage_send x lines_cleared x (lines_cleared >= 2)
      + tetris_bonus x (lines_cleared == 4)
      + opponent_danger x avg_opponent_height_ratio
      - survival x own_max_height_ratio^2
      + line_efficiency x lines_cleared^2
```

Values normalized to 0-1 range (e.g., `own_max_height / 20`). The quadratic survival term makes the bot increasingly conservative as its board fills.

## Module Changes

### BotStrategy

- New `score_battle_placement/3` — calls `score_placement/2` for base score, adds 6 battle terms.
- New `best_placement/6` clause for `:battle` — passes battle context through scoring. Uses same pruned 2-piece lookahead as `:hard`.
- `weights_for(:battle)` loads from `priv/battle_weights.json` (12 keys).
- No changes to `enumerate_placements/2`, `plan_actions/3`, or any placement mechanics.

### BotPlayer

- New struct field: `battle_context` — rebuilt on each `{:game_state, payload}`.
- `do_think/1` for `:battle` calls `best_placement/6` with battle context.
- `maybe_set_target/3` for `:battle` targets highest `max_height` opponent (closest to dying), tiebreaker by score.
- Uses same timing as `:hard` (50-100ms think, 50ms action).

### BotTrainer.BattleSimulation (new module)

Headless N-player battle loop. Pure functional, no GenServer or timers.

```elixir
def simulate_battle(genome, opponents, opts \\ [])
```

- Runs tick loop: each player picks best placement, places piece, clears lines, distributes garbage, checks eliminations.
- Returns placement rank and lines cleared.

Fitness: `evaluate/3` runs N battles, returns weighted score of avg placement rank + lines cleared.

### BotTrainer.Evolution

- `@weight_keys` extended with 6 new battle keys.
- New config field: `mode: :solo | :battle`.
- When `mode: :battle`, calls `BattleSimulation.evaluate/3` instead of `Simulation.evaluate/3`.

### Adaptive Opponent Strategy

During evolution loop:

1. **Phase 1 (solo opponents):** All 3 opponents use current solo `:hard` weights.
2. **Switch to co-evolution:** When best fitness improves < 1% for 5 consecutive generations.
3. **Co-evolution opponents:** `[best_genome_so_far, random_from_population, solo_hard_weights]`.
4. **Fallback:** If best fitness drops > 5% for 3 consecutive generations, switch back to solo opponents.

Tracked with simple counters in the evolution loop state.

### GameChannel

Add `"battle"` to the difficulty string match in `handle_in("add_bot", ...)`.

### WaitingRoom.tsx

Add "Battle" option to the bot difficulty dropdown.

## Output

Evolved weights saved to `priv/battle_weights.json` with all 12 keys plus metadata (generation, fitness, training mode).

## Out of Scope

- No changes to solo mode, `:easy`, `:medium`, or `:hard`
- No client-side game logic changes
- No protocol changes
- No new channels or socket events

## Testing

| Layer | Coverage |
|-------|----------|
| BotStrategy | `score_battle_placement/3` scores safer placements higher under garbage pressure; scores multi-line clears higher when opponents are tall |
| BotPlayer | Battle context extraction; target selection picks highest-board opponent |
| BattleSimulation | 4-player battle completes; garbage distributes correctly between players |
| Evolution | Adaptive switching triggers at thresholds; `:battle` mode produces 12-key genome |
| Integration | `:battle` bot joins room, plays game, doesn't crash |
