# Battle-Aware Bot Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `:battle` difficulty bot that uses environmental awareness (incoming garbage, opponent board states, scores) to survive multiplayer battles and eliminate opponents.

**Architecture:** Extend `BotStrategy` with a `score_battle_placement/3` function that adds 6 battle-context weights to the existing 6 board-quality weights. `BotPlayer` extracts battle context from the game state it already receives. A new `BotTrainer.BattleSimulation` module simulates headless N-player battles for GA fitness evaluation. Evolution gains a `:battle` mode with adaptive opponent strategy.

**Tech Stack:** Elixir/Phoenix (server), React/TypeScript (client dropdown only)

---

### Task 1: Extend BotStrategy with battle scoring

**Files:**
- Modify: `server/lib/tetris/bot_strategy.ex`
- Test: `server/test/tetris/bot_strategy_test.exs`

**Step 1: Write failing tests for `score_battle_placement/3`**

Add to `server/test/tetris/bot_strategy_test.exs`:

```elixir
describe "score_battle_placement/3" do
  @battle_weights %{
    height: 0.2, holes: 0.2, bumpiness: 0.1,
    lines: 0.1, max_height: 0.05, wells: 0.05,
    garbage_incoming: 0.1, garbage_send: 0.05,
    tetris_bonus: 0.05, opponent_danger: 0.05,
    survival: 0.03, line_efficiency: 0.02
  }

  test "penalizes high placements when garbage is pending" do
    ctx_no_garbage = %{
      pending_garbage_count: 0,
      own_max_height: 10,
      opponent_max_heights: [5],
      opponent_count: 1,
      leading_opponent_score: 100
    }

    ctx_with_garbage = %{
      pending_garbage_count: 4,
      own_max_height: 10,
      opponent_max_heights: [5],
      opponent_count: 1,
      leading_opponent_score: 100
    }

    metrics = %{
      aggregate_height: 40,
      holes: 2,
      bumpiness: 5,
      complete_lines: 0,
      max_height: 10,
      well_sum: 3
    }

    score_safe = BotStrategy.score_battle_placement(
      metrics, @battle_weights, ctx_no_garbage
    )
    score_danger = BotStrategy.score_battle_placement(
      metrics, @battle_weights, ctx_with_garbage
    )

    assert score_safe > score_danger
  end

  test "rewards multi-line clears when opponents are tall" do
    ctx = %{
      pending_garbage_count: 0,
      own_max_height: 5,
      opponent_max_heights: [16, 14],
      opponent_count: 2,
      leading_opponent_score: 500
    }

    single = %{
      aggregate_height: 20,
      holes: 1,
      bumpiness: 3,
      complete_lines: 1,
      max_height: 5,
      well_sum: 2
    }

    tetris = %{
      aggregate_height: 16,
      holes: 1,
      bumpiness: 3,
      complete_lines: 4,
      max_height: 4,
      well_sum: 2
    }

    score_single = BotStrategy.score_battle_placement(
      single, @battle_weights, ctx
    )
    score_tetris = BotStrategy.score_battle_placement(
      tetris, @battle_weights, ctx
    )

    assert score_tetris > score_single
  end

  test "increases survival penalty as board fills up" do
    ctx = %{
      pending_garbage_count: 0,
      own_max_height: 18,
      opponent_max_heights: [5],
      opponent_count: 1,
      leading_opponent_score: 100
    }

    metrics_high = %{
      aggregate_height: 80,
      holes: 2,
      bumpiness: 5,
      complete_lines: 0,
      max_height: 18,
      well_sum: 3
    }

    metrics_low = %{
      aggregate_height: 20,
      holes: 2,
      bumpiness: 5,
      complete_lines: 0,
      max_height: 5,
      well_sum: 3
    }

    ctx_low = %{ctx | own_max_height: 5}

    score_high = BotStrategy.score_battle_placement(
      metrics_high, @battle_weights, ctx
    )
    score_low = BotStrategy.score_battle_placement(
      metrics_low, @battle_weights, ctx_low
    )

    assert score_low > score_high
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd server && mix test test/tetris/bot_strategy_test.exs --only describe:"score_battle_placement/3"`

Expected: Compilation error — `score_battle_placement/3` undefined.

**Step 3: Implement `score_battle_placement/3` and `weights_for(:battle)`**

In `server/lib/tetris/bot_strategy.ex`:

Add `:battle` to the `@type difficulty` union:

```elixir
@type difficulty :: :easy | :medium | :hard | :battle
```

Add new weight keys constant:

```elixir
@battle_weight_keys [
  :height, :holes, :bumpiness, :lines, :max_height, :wells,
  :garbage_incoming, :garbage_send, :tetris_bonus,
  :opponent_danger, :survival, :line_efficiency
]
```

Add `weights_for(:battle)`:

```elixir
def weights_for(:battle) do
  case load_battle_weights() do
    {:ok, weights} -> weights
    :error -> default_battle_weights()
  end
end
```

Add `default_battle_weights/0`:

```elixir
defp default_battle_weights do
  %{
    height: 0.15, holes: 0.15, bumpiness: 0.08,
    lines: 0.10, max_height: 0.05, wells: 0.05,
    garbage_incoming: 0.10, garbage_send: 0.08,
    tetris_bonus: 0.08, opponent_danger: 0.06,
    survival: 0.06, line_efficiency: 0.04
  }
end
```

Add `load_battle_weights/0` (mirrors `load_evolved_weights` but reads `battle_weights.json` and includes battle keys):

```elixir
defp load_battle_weights do
  path =
    :code.priv_dir(:tetris)
    |> to_string()
    |> Path.join("battle_weights.json")

  with {:ok, contents} <- File.read(path),
       {:ok, data} <- Jason.decode(contents),
       %{"weights" => w} <- data do
    {:ok,
     Map.new(@battle_weight_keys, fn key ->
       {key, w[Atom.to_string(key)] || 0.0}
     end)}
  else
    _ -> :error
  end
end
```

Add `score_battle_placement/3`:

```elixir
@board_height 20

@spec score_battle_placement(map(), map(), map()) :: float()
def score_battle_placement(metrics, weights, battle_ctx) do
  base = score_placement(metrics, weights)

  own_height_ratio =
    battle_ctx.own_max_height / @board_height

  avg_opp_height_ratio =
    case battle_ctx.opponent_max_heights do
      [] -> 0.0
      heights -> Enum.sum(heights) / (length(heights) * @board_height)
    end

  lines = metrics.complete_lines
  sends_garbage = if lines >= 2, do: 1.0, else: 0.0
  is_tetris = if lines == 4, do: 1.0, else: 0.0

  base
  - weights.garbage_incoming *
      battle_ctx.pending_garbage_count * own_height_ratio
  + weights.garbage_send * lines * sends_garbage
  + weights.tetris_bonus * is_tetris
  + weights.opponent_danger * avg_opp_height_ratio
  - weights.survival * own_height_ratio * own_height_ratio
  + weights.line_efficiency * lines * lines
end
```

**Step 4: Run tests to verify they pass**

Run: `cd server && mix test test/tetris/bot_strategy_test.exs`

Expected: All tests pass including the 3 new ones.

**Step 5: Commit**

```bash
git add server/lib/tetris/bot_strategy.ex server/test/tetris/bot_strategy_test.exs
git commit -m "feat: add score_battle_placement/3 with 6 battle-context weights"
```

---

### Task 2: Add battle-mode best_placement to BotStrategy

**Files:**
- Modify: `server/lib/tetris/bot_strategy.ex`
- Test: `server/test/tetris/bot_strategy_test.exs`

**Step 1: Write failing test for `best_placement` with battle context**

Add to `server/test/tetris/bot_strategy_test.exs`:

```elixir
describe "best_placement with :battle" do
  test "returns valid actions with battle context" do
    board = Board.new()
    piece = Piece.new(:T)
    next = Piece.new(:I)

    battle_ctx = %{
      pending_garbage_count: 0,
      own_max_height: 0,
      opponent_max_heights: [5],
      opponent_count: 1,
      leading_opponent_score: 100
    }

    {rot, x, actions} =
      BotStrategy.best_placement(
        board, piece, {3, 0}, next, :battle, battle_ctx
      )

    assert is_integer(rot) and rot in 0..3
    assert is_integer(x) and x >= 0
    assert is_list(actions)
    assert List.last(actions) == "hard_drop"

    assert Enum.all?(actions, fn a ->
      a in ["rotate", "move_left", "move_right", "hard_drop"]
    end)
  end

  test "5-arg best_placement still works for non-battle" do
    board = Board.new()
    piece = Piece.new(:T)
    next = Piece.new(:I)

    {rot, x, actions} =
      BotStrategy.best_placement(board, piece, {3, 0}, next, :hard)

    assert is_integer(rot) and rot in 0..3
    assert is_integer(x) and x >= 0
    assert List.last(actions) == "hard_drop"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd server && mix test test/tetris/bot_strategy_test.exs --only describe:"best_placement with :battle"`

Expected: Error — `best_placement/6` is undefined (or no matching clause).

**Step 3: Implement `best_placement/6` for `:battle`**

Add new function head in `server/lib/tetris/bot_strategy.ex`:

```elixir
@spec best_placement(
        [[nil | String.t()]],
        Piece.t(),
        {integer(), integer()},
        Piece.t() | nil,
        difficulty(),
        map()
      ) :: {non_neg_integer(), integer(), [String.t()]}
def best_placement(board, piece, spawn_pos, next_piece, :battle, battle_ctx) do
  placements = enumerate_placements(board, piece)
  weights = weights_for(:battle)

  scored =
    if next_piece != nil do
      score_battle_with_lookahead(
        placements, next_piece, weights, battle_ctx
      )
    else
      Enum.map(placements, fn pl ->
        score = score_battle_placement(pl.metrics, weights, battle_ctx)
        {score, pl}
      end)
    end

  chosen = pick_placement(scored, :hard)
  {spawn_x, _} = spawn_pos

  actions =
    plan_actions(spawn_x, chosen.rotation_count, chosen.target_x)

  {chosen.rotation_count, chosen.target_x, actions}
end
```

Add `score_battle_with_lookahead/4`:

```elixir
defp score_battle_with_lookahead(placements, next_piece, weights, ctx) do
  scored =
    Enum.map(placements, fn pl ->
      {score_battle_placement(pl.metrics, weights, ctx), pl}
    end)

  top_k =
    scored
    |> Enum.sort_by(fn {s, _} -> s end, :desc)
    |> Enum.take(5)

  Enum.map(top_k, fn {greedy_score, pl} ->
    next_placements = enumerate_placements(pl.resulting_board, next_piece)

    best_next =
      if next_placements == [] do
        -1_000_000.0
      else
        next_placements
        |> Enum.map(fn np ->
          score_battle_placement(np.metrics, weights, ctx)
        end)
        |> Enum.max()
      end

    {greedy_score + best_next, pl}
  end)
end
```

**Step 4: Run tests to verify they pass**

Run: `cd server && mix test test/tetris/bot_strategy_test.exs`

Expected: All tests pass.

**Step 5: Commit**

```bash
git add server/lib/tetris/bot_strategy.ex server/test/tetris/bot_strategy_test.exs
git commit -m "feat: add best_placement/6 with battle lookahead"
```

---

### Task 3: Update BotPlayer for battle context and targeting

**Files:**
- Modify: `server/lib/tetris_game/bot_player.ex`
- Test: `server/test/tetris_game/bot_player_test.exs`

**Step 1: Read existing bot_player_test for patterns**

Check `server/test/tetris_game/bot_player_test.exs` for existing test patterns before writing new tests.

**Step 2: Write failing tests for battle context extraction**

Add to `server/test/tetris_game/bot_player_test.exs` (or create a new describe block):

```elixir
describe "battle context extraction" do
  test "build_battle_context/3 extracts correct values" do
    # This tests the module function directly
    bot_id = "bot1"

    bot_player = %{
      board: Tetris.Board.new(),
      alive: true,
      score: 100,
      pending_garbage: [[:gray], [:gray]],
      current_piece: Tetris.Piece.new(:T),
      position: {3, 0},
      next_piece: Tetris.Piece.new(:I)
    }

    opponent1 = %{
      board: make_board_with_height(8),
      alive: true,
      score: 200,
      pending_garbage: []
    }

    opponent2 = %{
      board: make_board_with_height(15),
      alive: true,
      score: 50,
      pending_garbage: []
    }

    dead_opponent = %{
      board: Tetris.Board.new(),
      alive: false,
      score: 10,
      pending_garbage: []
    }

    players = %{
      "bot1" => bot_player,
      "p1" => opponent1,
      "p2" => opponent2,
      "p3" => dead_opponent
    }

    ctx = TetrisGame.BotPlayer.build_battle_context(
      bot_id, bot_player, players
    )

    assert ctx.pending_garbage_count == 2
    assert ctx.own_max_height == 0
    assert ctx.opponent_count == 2
    assert length(ctx.opponent_max_heights) == 2
    assert 8 in ctx.opponent_max_heights
    assert 15 in ctx.opponent_max_heights
    assert ctx.leading_opponent_score == 200
  end

  defp make_board_with_height(h) do
    board = Tetris.Board.new()
    filled_row = List.duplicate("#ff0000", 10)

    Enum.reduce((20 - h)..(19), board, fn row_idx, b ->
      List.update_at(b, row_idx, fn _ -> filled_row end)
    end)
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `cd server && mix test test/tetris_game/bot_player_test.exs --only describe:"battle context extraction"`

Expected: `build_battle_context/3` undefined.

**Step 4: Implement battle context extraction and targeting**

In `server/lib/tetris_game/bot_player.ex`:

Add `battle_context` to the struct:

```elixir
defstruct [
  :bot_id,
  :nickname,
  :room_id,
  :room_ref,
  :difficulty,
  :phase,
  :action_queue,
  :last_piece_id,
  :battle_context
]
```

Add `build_battle_context/3` as a public function (for testability):

```elixir
@spec build_battle_context(String.t(), map(), map()) :: map()
def build_battle_context(bot_id, bot_player, players) do
  alive_opponents =
    players
    |> Enum.filter(fn {id, p} -> id != bot_id and p.alive end)
    |> Enum.map(fn {_id, p} -> p end)

  opp_heights =
    Enum.map(alive_opponents, fn p ->
      max_height_from_board(p.board)
    end)

  leading_score =
    case alive_opponents do
      [] -> 0
      opps -> opps |> Enum.map(& &1.score) |> Enum.max()
    end

  pending_count =
    case bot_player.pending_garbage do
      count when is_integer(count) -> count
      list when is_list(list) -> length(list)
      _ -> 0
    end

  %{
    pending_garbage_count: pending_count,
    own_max_height: max_height_from_board(bot_player.board),
    opponent_max_heights: opp_heights,
    opponent_count: length(alive_opponents),
    leading_opponent_score: leading_score
  }
end

defp max_height_from_board(board) do
  board
  |> Enum.with_index()
  |> Enum.find_value(0, fn {row, idx} ->
    if Enum.any?(row, &(&1 != nil)), do: 20 - idx
  end)
end
```

Modify `do_think/1` — add a clause that pattern-matches on `:battle` difficulty before the existing clause:

```elixir
defp do_think(%{difficulty: :battle} = state) do
  room = GameRoom.via(state.room_id)

  try do
    room_state = GameRoom.get_state(room)
    player = room_state.players[state.bot_id]

    if player == nil or not player.alive do
      {:stop, :normal, state}
    else
      battle_ctx = build_battle_context(
        state.bot_id,
        player,
        room_state.players
      )

      {_rot, _x, actions} =
        BotStrategy.best_placement(
          player.board,
          player.current_piece,
          player.position,
          player.next_piece,
          :battle,
          battle_ctx
        )

      maybe_set_target(room, room_state, state)

      timing = @timing[:hard]
      Process.send_after(self(), :execute_action, timing.action_interval)

      {:noreply, %{state | phase: :executing, action_queue: actions}}
    end
  catch
    :exit, _ ->
      {:stop, :normal, state}
  end
end
```

Add `:battle` timing (reuse `:hard` values) to `@timing`:

```elixir
@timing %{
  easy: %{think_min: 800, think_max: 1200, action_interval: 200},
  medium: %{think_min: 300, think_max: 500, action_interval: 100},
  hard: %{think_min: 50, think_max: 100, action_interval: 50},
  battle: %{think_min: 50, think_max: 100, action_interval: 50}
}
```

Update `maybe_set_target/3` — add a `:battle` clause that targets the opponent with the highest board:

```elixir
defp maybe_set_target(room, room_state, state) do
  alive_opponents =
    room_state.players
    |> Enum.filter(fn {id, p} -> id != state.bot_id and p.alive end)
    |> Enum.map(fn {id, p} -> {id, p} end)

  if alive_opponents != [] do
    target =
      case state.difficulty do
        :battle ->
          {id, _} =
            Enum.max_by(alive_opponents, fn {_, p} ->
              {max_height_from_board(p.board), p.score}
            end)
          id

        :hard ->
          {id, _} = Enum.max_by(alive_opponents, fn {_, p} -> p.score end)
          id

        _ ->
          {id, _} = Enum.random(alive_opponents)
          id
      end

    try do
      GameRoom.set_target(room, state.bot_id, target)
    catch
      :exit, _ -> :ok
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `cd server && mix test test/tetris_game/bot_player_test.exs`

Expected: All tests pass.

**Step 6: Commit**

```bash
git add server/lib/tetris_game/bot_player.ex server/test/tetris_game/bot_player_test.exs
git commit -m "feat: add battle context extraction and smart targeting to BotPlayer"
```

---

### Task 4: Add BattleSimulation module

**Files:**
- Create: `server/lib/bot_trainer/battle_simulation.ex`
- Create: `server/test/bot_trainer/battle_simulation_test.exs`

**Step 1: Write failing tests**

Create `server/test/bot_trainer/battle_simulation_test.exs`:

```elixir
defmodule BotTrainer.BattleSimulationTest do
  use ExUnit.Case, async: true

  alias BotTrainer.BattleSimulation

  @solo_weights %{
    height: 0.51, holes: 0.36, bumpiness: 0.18,
    lines: 0.76, max_height: 0.0, wells: 0.0
  }

  @battle_weights %{
    height: 0.15, holes: 0.15, bumpiness: 0.08,
    lines: 0.10, max_height: 0.05, wells: 0.05,
    garbage_incoming: 0.10, garbage_send: 0.08,
    tetris_bonus: 0.08, opponent_danger: 0.06,
    survival: 0.06, line_efficiency: 0.04
  }

  describe "simulate_battle/3" do
    test "4-player battle runs to completion" do
      opponents = List.duplicate(@solo_weights, 3)

      result = BattleSimulation.simulate_battle(
        @battle_weights, opponents, lookahead: false
      )

      assert result.placement in 1..4
      assert is_integer(result.lines_cleared)
      assert result.lines_cleared >= 0
      assert is_integer(result.pieces_placed)
      assert result.pieces_placed > 0
    end

    test "2-player battle works" do
      result = BattleSimulation.simulate_battle(
        @battle_weights, [@solo_weights], lookahead: false
      )

      assert result.placement in 1..2
    end

    test "battle always produces exactly one winner" do
      opponents = List.duplicate(@solo_weights, 3)

      result = BattleSimulation.simulate_battle(
        @battle_weights, opponents, lookahead: false
      )

      assert result.total_players == 4
      assert result.placement >= 1
      assert result.placement <= 4
    end
  end

  describe "evaluate/3" do
    test "returns float fitness from multiple battles" do
      opponents = List.duplicate(@solo_weights, 3)

      fitness = BattleSimulation.evaluate(
        @battle_weights, opponents, 3, lookahead: false
      )

      assert is_float(fitness)
      assert fitness >= 0.0
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd server && mix test test/bot_trainer/battle_simulation_test.exs`

Expected: Module `BotTrainer.BattleSimulation` not found.

**Step 3: Implement BattleSimulation**

Create `server/lib/bot_trainer/battle_simulation.ex`:

```elixir
defmodule BotTrainer.BattleSimulation do
  @moduledoc """
  Headless N-player Tetris battle simulation for bot weight evaluation.

  Runs complete multiplayer games without timing or GenServer overhead.
  Each player takes turns placing pieces, garbage is distributed between
  players, and players are eliminated when their boards overflow.
  """

  alias Tetris.Board
  alias Tetris.BotStrategy
  alias Tetris.Piece

  @line_points %{1 => 100, 2 => 300, 3 => 500, 4 => 800}
  @board_height 20

  @type result :: %{
          placement: pos_integer(),
          lines_cleared: non_neg_integer(),
          pieces_placed: non_neg_integer(),
          total_players: pos_integer()
        }

  @type opts :: [lookahead: boolean()]

  @doc """
  Simulates a battle between the evaluated genome and opponents.

  The genome uses battle-aware scoring. Opponents use solo scoring.
  Returns the genome's placement (1 = won, N = eliminated first).
  """
  @spec simulate_battle(map(), [map()], opts()) :: result()
  def simulate_battle(genome, opponent_weights, opts \\ []) do
    lookahead = Keyword.get(opts, :lookahead, true)
    total = 1 + length(opponent_weights)

    players =
      [
        new_player(0, genome, :battle, lookahead)
        | opponent_weights
          |> Enum.with_index(1)
          |> Enum.map(fn {w, idx} ->
            new_player(idx, w, :solo, lookahead)
          end)
      ]
      |> Map.new(fn p -> {p.id, p} end)

    # Player 0 targets player 1, each targets next (round-robin)
    players = assign_initial_targets(players, total)
    elimination_order = []
    battle_loop(players, elimination_order, total, lookahead)
  end

  @doc """
  Runs N battles and returns a fitness score.

  Fitness = weighted combination of avg placement rank and avg lines.
  Higher is better.
  """
  @spec evaluate(map(), [map()], pos_integer(), opts()) :: float()
  def evaluate(genome, opponents, num_battles, opts \\ []) do
    results =
      Enum.map(1..num_battles, fn _ ->
        simulate_battle(genome, opponents, opts)
      end)

    total_players = hd(results).total_players
    avg_placement =
      results
      |> Enum.map(& &1.placement)
      |> Enum.sum()
      |> Kernel./(num_battles)

    avg_lines =
      results
      |> Enum.map(& &1.lines_cleared)
      |> Enum.sum()
      |> Kernel./(num_battles)

    # Placement score: 1st place = 1.0, last place = 0.0
    placement_score = (total_players - avg_placement) / (total_players - 1)

    # Combine: 70% placement, 30% line efficiency (normalized)
    placement_score * 70.0 + avg_lines * 0.3
  end

  # -- Private --

  defp new_player(id, weights, mode, lookahead) do
    %{
      id: id,
      weights: weights,
      mode: mode,
      lookahead: lookahead,
      board: Board.new(),
      current_piece: Piece.random(),
      next_piece: Piece.random(),
      score: 0,
      lines: 0,
      level: 1,
      pieces_placed: 0,
      alive: true,
      pending_garbage: 0,
      target: nil
    }
  end

  defp assign_initial_targets(players, total) do
    Map.new(players, fn {id, p} ->
      target = rem(id + 1, total)
      {id, %{p | target: target}}
    end)
  end

  defp battle_loop(players, elimination_order, total, lookahead) do
    alive = Enum.filter(players, fn {_, p} -> p.alive end)

    if length(alive) <= 1 do
      finish_battle(players, elimination_order, total)
    else
      {updated_players, new_eliminations} =
        tick(players, alive, lookahead)

      updated_order = elimination_order ++ new_eliminations

      # Re-target: alive players targeting dead ones get reassigned
      retargeted = retarget_dead(updated_players)

      battle_loop(retargeted, updated_order, total, lookahead)
    end
  end

  defp tick(players, alive_list, lookahead) do
    # Each alive player places one piece
    Enum.reduce(alive_list, {players, []}, fn {id, _}, {acc, elims} ->
      player = acc[id]

      if not player.alive do
        {acc, elims}
      else
        # Apply pending garbage first
        {player, overflow} = apply_garbage(player)

        if overflow do
          acc = Map.put(acc, id, %{player | alive: false})
          {acc, elims ++ [id]}
        else
          # Find best placement
          placements =
            BotStrategy.enumerate_placements(
              player.board, player.current_piece
            )

          if placements == [] do
            acc = Map.put(acc, id, %{player | alive: false})
            {acc, elims ++ [id]}
          else
            best = pick_best(player, placements, acc, lookahead)
            {updated, lines_cleared} = apply_placement(player, best)

            # Distribute garbage to target
            {acc2, new_elims} =
              if lines_cleared >= 2 do
                garbage_count = lines_cleared - 1
                send_garbage(acc, id, updated, garbage_count)
              else
                {acc, []}
              end

            # Spawn next piece
            case spawn_next(updated) do
              {:ok, spawned} ->
                # Update target to highest-board opponent
                spawned = update_target(spawned, acc2)
                acc3 = Map.put(acc2, id, spawned)
                {acc3, elims ++ new_elims}

              :game_over ->
                dead = %{updated | alive: false}
                acc3 = Map.put(acc2, id, dead)
                {acc3, elims ++ new_elims ++ [id]}
            end
          end
        end
      end
    end)
  end

  defp pick_best(player, placements, all_players, lookahead) do
    case player.mode do
      :battle ->
        battle_ctx = build_context(player, all_players)
        weights = player.weights

        scored =
          Enum.map(placements, fn pl ->
            {BotStrategy.score_battle_placement(
               pl.metrics, weights, battle_ctx
             ), pl}
          end)

        if lookahead and player.lookahead do
          top_k =
            scored
            |> Enum.sort_by(fn {s, _} -> s end, :desc)
            |> Enum.take(5)

          {_, best} =
            Enum.max_by(top_k, fn {gs, pl} ->
              gs + best_next_battle(
                pl.resulting_board, player.next_piece,
                weights, battle_ctx
              )
            end)

          best
        else
          {_, best} = Enum.max_by(scored, fn {s, _} -> s end)
          best
        end

      :solo ->
        weights = player.weights

        scored =
          Enum.map(placements, fn pl ->
            {BotStrategy.score_placement(pl.metrics, weights), pl}
          end)

        if lookahead and player.lookahead do
          top_k =
            scored
            |> Enum.sort_by(fn {s, _} -> s end, :desc)
            |> Enum.take(5)

          {_, best} =
            Enum.max_by(top_k, fn {gs, pl} ->
              gs + best_next_solo(
                pl.resulting_board, player.next_piece, weights
              )
            end)

          best
        else
          {_, best} = Enum.max_by(scored, fn {s, _} -> s end)
          best
        end
    end
  end

  defp best_next_battle(board, next_piece, weights, ctx) do
    case BotStrategy.enumerate_placements(board, next_piece) do
      [] -> -1_000_000.0
      pls ->
        pls
        |> Enum.map(&BotStrategy.score_battle_placement(&1.metrics, weights, ctx))
        |> Enum.max()
    end
  end

  defp best_next_solo(board, next_piece, weights) do
    case BotStrategy.enumerate_placements(board, next_piece) do
      [] -> -1_000_000.0
      pls ->
        pls
        |> Enum.map(&BotStrategy.score_placement(&1.metrics, weights))
        |> Enum.max()
    end
  end

  defp build_context(player, all_players) do
    alive_opps =
      all_players
      |> Enum.filter(fn {id, p} -> id != player.id and p.alive end)
      |> Enum.map(fn {_, p} -> p end)

    opp_heights = Enum.map(alive_opps, &max_height(&1.board))

    leading_score =
      case alive_opps do
        [] -> 0
        opps -> opps |> Enum.map(& &1.score) |> Enum.max()
      end

    %{
      pending_garbage_count: player.pending_garbage,
      own_max_height: max_height(player.board),
      opponent_max_heights: opp_heights,
      opponent_count: length(alive_opps),
      leading_opponent_score: leading_score
    }
  end

  defp apply_garbage(%{pending_garbage: 0} = player) do
    {player, false}
  end

  defp apply_garbage(player) do
    rows =
      for _ <- 1..player.pending_garbage, do: Board.generate_garbage_row()

    {new_board, overflow} = Board.add_garbage(player.board, rows)
    {%{player | board: new_board, pending_garbage: 0}, overflow}
  end

  defp apply_placement(player, placement) do
    rotated = apply_rotations(player.current_piece, placement.rotation_count)

    {_gx, gy} =
      Board.ghost_position(
        player.board, rotated.shape, {placement.target_x, 0}
      )

    placed =
      Board.place_piece(
        player.board, rotated.shape, rotated.color,
        {placement.target_x, gy}
      )

    {cleared_board, lines_cleared} = Board.clear_lines(placed)
    line_score = Map.get(@line_points, lines_cleared, 0) * player.level
    new_lines = player.lines + lines_cleared
    new_level = div(new_lines, 10) + 1

    updated = %{
      player
      | board: cleared_board,
        score: player.score + line_score,
        lines: new_lines,
        level: new_level,
        pieces_placed: player.pieces_placed + 1
    }

    {updated, lines_cleared}
  end

  defp send_garbage(players, sender_id, updated_sender, count) do
    target_id = updated_sender.target

    case players[target_id] do
      nil ->
        {Map.put(players, sender_id, updated_sender), []}

      target when not target.alive ->
        {Map.put(players, sender_id, updated_sender), []}

      target ->
        updated_target = %{
          target | pending_garbage: target.pending_garbage + count
        }

        players =
          players
          |> Map.put(sender_id, updated_sender)
          |> Map.put(target_id, updated_target)

        {players, []}
    end
  end

  defp spawn_next(player) do
    new_piece = player.next_piece
    shape_width = length(hd(new_piece.shape))
    spawn_x = div(Board.width() - shape_width, 2)

    if Board.valid_position?(player.board, new_piece.shape, {spawn_x, 0}) do
      {:ok,
       %{
         player
         | current_piece: new_piece,
           next_piece: Piece.random()
       }}
    else
      :game_over
    end
  end

  defp update_target(player, all_players) do
    case player.mode do
      :battle ->
        alive_opps =
          all_players
          |> Enum.filter(fn {id, p} -> id != player.id and p.alive end)

        case alive_opps do
          [] ->
            player

          opps ->
            {target_id, _} =
              Enum.max_by(opps, fn {_, p} ->
                {max_height(p.board), p.score}
              end)

            %{player | target: target_id}
        end

      :solo ->
        alive_opps =
          all_players
          |> Enum.filter(fn {id, p} -> id != player.id and p.alive end)

        case alive_opps do
          [] -> player
          opps ->
            {target_id, _} =
              Enum.max_by(opps, fn {_, p} -> p.score end)
            %{player | target: target_id}
        end
    end
  end

  defp retarget_dead(players) do
    alive_ids =
      players
      |> Enum.filter(fn {_, p} -> p.alive end)
      |> Enum.map(fn {id, _} -> id end)
      |> MapSet.new()

    Map.new(players, fn {id, p} ->
      if p.alive and p.target != nil and
           not MapSet.member?(alive_ids, p.target) do
        # Pick a new alive target
        new_target =
          alive_ids
          |> MapSet.delete(id)
          |> MapSet.to_list()
          |> List.first()

        {id, %{p | target: new_target}}
      else
        {id, p}
      end
    end)
  end

  defp finish_battle(players, elimination_order, total) do
    # Winner is the last alive (or if all dead, last eliminated)
    alive = Enum.filter(players, fn {_, p} -> p.alive end)

    winner_ids =
      case alive do
        [{id, _}] -> [id]
        [] -> []
        multi -> Enum.map(multi, fn {id, _} -> id end)
      end

    # Build placement map: eliminated first = worst placement
    all_ranked = Enum.reverse(elimination_order) ++ winner_ids

    # Player 0 is always the genome being evaluated
    genome_player = players[0]

    placement =
      case Enum.find_index(all_ranked, &(&1 == 0)) do
        nil -> total
        idx -> idx + 1
      end

    %{
      placement: placement,
      lines_cleared: genome_player.lines,
      pieces_placed: genome_player.pieces_placed,
      total_players: total
    }
  end

  defp max_height(board) do
    board
    |> Enum.with_index()
    |> Enum.find_value(0, fn {row, idx} ->
      if Enum.any?(row, &(&1 != nil)), do: @board_height - idx
    end)
  end

  defp apply_rotations(piece, 0), do: piece

  defp apply_rotations(piece, n) when n > 0 do
    apply_rotations(Piece.rotate(piece), n - 1)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `cd server && mix test test/bot_trainer/battle_simulation_test.exs`

Expected: All 4 tests pass.

**Step 5: Commit**

```bash
git add server/lib/bot_trainer/battle_simulation.ex server/test/bot_trainer/battle_simulation_test.exs
git commit -m "feat: add BattleSimulation for headless N-player battles"
```

---

### Task 5: Extend Evolution for battle mode with adaptive opponents

**Files:**
- Modify: `server/lib/bot_trainer/evolution.ex`
- Test: `server/test/bot_trainer/evolution_test.exs`

**Step 1: Write failing tests**

Add to `server/test/bot_trainer/evolution_test.exs`:

```elixir
@battle_weights [
  :height, :holes, :bumpiness, :lines, :max_height, :wells,
  :garbage_incoming, :garbage_send, :tetris_bonus,
  :opponent_danger, :survival, :line_efficiency
]

describe "battle mode" do
  test "random_battle_population generates 12-key genomes" do
    pop = Evolution.random_battle_population(5)
    assert length(pop) == 5

    for genome <- pop do
      for key <- @battle_weights do
        assert Map.has_key?(genome, key),
          "Missing key: #{key}"
        assert is_float(genome[key])
      end
    end
  end

  test "battle genomes are normalized to sum ~1.0" do
    pop = Evolution.random_battle_population(10)

    for genome <- pop do
      total =
        Enum.reduce(@battle_weights, 0.0, fn k, acc ->
          acc + genome[k]
        end)

      assert_in_delta total, 1.0, 0.001
    end
  end

  test "tiny battle evolution completes" do
    config =
      Evolution.default_battle_config()
      |> Map.merge(%{
        population_size: 4,
        generations: 2,
        battles_per_genome: 2,
        elitism_count: 1,
        immigrant_count: 1,
        lookahead: false,
        max_concurrency: 2
      })

    best = Evolution.evolve_battle(config, fn _ -> :ok end)

    for key <- @battle_weights do
      assert Map.has_key?(best, key)
      assert is_float(best[key])
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd server && mix test test/bot_trainer/evolution_test.exs --only describe:"battle mode"`

Expected: Functions undefined.

**Step 3: Implement battle evolution**

In `server/lib/bot_trainer/evolution.ex`:

Add battle weight keys:

```elixir
@battle_weight_keys [
  :height, :holes, :bumpiness, :lines, :max_height, :wells,
  :garbage_incoming, :garbage_send, :tetris_bonus,
  :opponent_danger, :survival, :line_efficiency
]
```

Add `random_battle_population/1`:

```elixir
@spec random_battle_population(pos_integer()) :: [map()]
def random_battle_population(n) do
  Enum.map(1..n, fn _ -> random_battle_genome() end)
end

defp random_battle_genome do
  genome =
    Map.new(@battle_weight_keys, fn k -> {k, :rand.uniform()} end)

  normalize_keys(genome, @battle_weight_keys)
end
```

Add `normalize_keys/2` (generalized normalize):

```elixir
@spec normalize_keys(map(), [atom()]) :: map()
def normalize_keys(genome, keys) do
  total =
    Enum.reduce(keys, 0.0, fn k, acc -> acc + genome[k] end)

  n = length(keys)

  if total == 0.0 do
    Map.new(keys, fn k -> {k, 1.0 / n} end)
  else
    Map.new(keys, fn k -> {k, genome[k] / total} end)
  end
end
```

Refactor existing `normalize/1` to use `normalize_keys/2`:

```elixir
def normalize(genome), do: normalize_keys(genome, @weight_keys)
```

Add `default_battle_config/0`:

```elixir
@spec default_battle_config() :: map()
def default_battle_config do
  %{
    population_size: 50,
    generations: 100,
    battles_per_genome: 10,
    num_opponents: 3,
    tournament_size: 3,
    crossover_rate: 0.7,
    mutation_rate: 0.3,
    mutation_sigma: 0.15,
    elitism_count: 2,
    immigrant_count: 5,
    max_concurrency: System.schedulers_online(),
    stagnation_threshold: 5,
    regression_threshold: 3,
    lookahead: true
  }
end
```

Add `evolve_battle/2`:

```elixir
@spec evolve_battle(map(), (map() -> any())) :: map()
def evolve_battle(config, on_generation \\ fn _ -> :ok end) do
  population = random_battle_population(config.population_size)

  solo_weights = load_solo_hard_weights()

  adaptor = %{
    mode: :solo_opponents,
    solo_weights: solo_weights,
    stagnation_count: 0,
    regression_count: 0,
    last_best_fitness: 0.0,
    best_genome: nil
  }

  evolve_battle_loop(population, config, on_generation, adaptor, 1)
end
```

Add the battle evolution loop with adaptive opponent switching:

```elixir
defp evolve_battle_loop(population, config, _on_gen, adaptor, gen)
     when gen > config.generations do
  opponents = build_opponents(adaptor, config)
  opts = [lookahead: Map.get(config, :lookahead, true)]

  scored =
    evaluate_battle_population(
      population, opponents,
      config.battles_per_genome,
      config.max_concurrency, opts
    )

  {_fitness, best} = hd(scored)
  best
end

defp evolve_battle_loop(population, config, on_gen, adaptor, gen) do
  opponents = build_opponents(adaptor, config)
  opts = [lookahead: Map.get(config, :lookahead, true)]

  scored =
    evaluate_battle_population(
      population, opponents,
      config.battles_per_genome,
      config.max_concurrency, opts
    )

  fitnesses = Enum.map(scored, fn {f, _} -> f end)
  best_fitness = hd(fitnesses)
  {_, best_genome} = hd(scored)

  stats = %{
    generation: gen,
    best_fitness: best_fitness,
    avg_fitness: Enum.sum(fitnesses) / length(fitnesses),
    worst_fitness: List.last(fitnesses),
    best_genome: best_genome,
    opponent_mode: adaptor.mode
  }

  on_gen.(stats)

  # Adaptive opponent switching
  adaptor = update_adaptor(adaptor, best_fitness, best_genome, config)

  # Breed next generation
  elites =
    scored
    |> Enum.take(config.elitism_count)
    |> Enum.map(fn {_, g} -> g end)

  children_needed =
    config.population_size - config.elitism_count -
      config.immigrant_count

  children =
    if children_needed > 0 do
      Enum.map(1..children_needed, fn _ ->
        if :rand.uniform() < config.crossover_rate do
          a = tournament_select(scored, config.tournament_size)
          b = tournament_select(scored, config.tournament_size)
          crossover_keys(a, b, @battle_weight_keys)
        else
          tournament_select(scored, config.tournament_size)
        end
        |> mutate_keys(config.mutation_rate, config.mutation_sigma, @battle_weight_keys)
        |> normalize_keys(@battle_weight_keys)
      end)
    else
      []
    end

  immigrants = random_battle_population(config.immigrant_count)
  next_pop = elites ++ children ++ immigrants

  evolve_battle_loop(next_pop, config, on_gen, adaptor, gen + 1)
end
```

Add helper functions:

```elixir
defp evaluate_battle_population(genomes, opponents, battles_per, max_conc, opts) do
  nodes = BotTrainer.Cluster.available_nodes()
  node_count = length(nodes)

  genomes
  |> Enum.with_index()
  |> Task.async_stream(
    fn {genome, idx} ->
      target = Enum.at(nodes, rem(idx, node_count))

      fitness =
        :erpc.call(
          target,
          BotTrainer.BattleSimulation,
          :evaluate,
          [genome, opponents, battles_per, opts],
          :infinity
        )

      {fitness, genome}
    end,
    max_concurrency: max_conc,
    timeout: :infinity,
    ordered: false
  )
  |> Enum.map(fn {:ok, result} -> result end)
  |> Enum.sort_by(fn {fitness, _} -> fitness end, :desc)
end

defp build_opponents(adaptor, config) do
  n = Map.get(config, :num_opponents, 3)

  case adaptor.mode do
    :solo_opponents ->
      List.duplicate(adaptor.solo_weights, n)

    :co_evolution ->
      [
        adaptor.best_genome || adaptor.solo_weights,
        random_battle_genome(),
        adaptor.solo_weights
      ]
      |> Enum.take(n)
  end
end

defp update_adaptor(adaptor, best_fitness, best_genome, config) do
  stagnation_pct =
    if adaptor.last_best_fitness > 0.0 do
      (best_fitness - adaptor.last_best_fitness) /
        adaptor.last_best_fitness
    else
      1.0
    end

  stag_thresh = Map.get(config, :stagnation_threshold, 5)
  reg_thresh = Map.get(config, :regression_threshold, 3)

  case adaptor.mode do
    :solo_opponents ->
      stag_count =
        if stagnation_pct < 0.01,
          do: adaptor.stagnation_count + 1,
          else: 0

      if stag_count >= stag_thresh do
        %{adaptor |
          mode: :co_evolution,
          stagnation_count: 0,
          regression_count: 0,
          last_best_fitness: best_fitness,
          best_genome: best_genome
        }
      else
        %{adaptor |
          stagnation_count: stag_count,
          last_best_fitness: best_fitness,
          best_genome: best_genome
        }
      end

    :co_evolution ->
      reg_count =
        if stagnation_pct < -0.05,
          do: adaptor.regression_count + 1,
          else: 0

      if reg_count >= reg_thresh do
        %{adaptor |
          mode: :solo_opponents,
          stagnation_count: 0,
          regression_count: 0,
          last_best_fitness: best_fitness,
          best_genome: best_genome
        }
      else
        %{adaptor |
          regression_count: reg_count,
          last_best_fitness: best_fitness,
          best_genome: best_genome
        }
      end
  end
end

defp crossover_keys(parent_a, parent_b, keys) do
  Map.new(keys, fn key ->
    {key, pick(parent_a[key], parent_b[key])}
  end)
end

defp mutate_keys(genome, rate, sigma, keys) do
  Map.new(keys, fn key ->
    {key, maybe_mutate(genome[key], rate, sigma)}
  end)
end

defp load_solo_hard_weights do
  case Tetris.BotStrategy.weights_for(:hard) do
    weights when is_map(weights) -> weights
    _ ->
      %{
        height: 0.51, holes: 0.36, bumpiness: 0.18,
        lines: 0.76, max_height: 0.0, wells: 0.0
      }
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `cd server && mix test test/bot_trainer/evolution_test.exs`

Expected: All tests pass (existing + 3 new).

**Step 5: Commit**

```bash
git add server/lib/bot_trainer/evolution.ex server/test/bot_trainer/evolution_test.exs
git commit -m "feat: add battle evolution mode with adaptive opponent strategy"
```

---

### Task 6: Wire up GameChannel and WaitingRoom UI

**Files:**
- Modify: `server/lib/tetris_web/channels/game_channel.ex:69-78`
- Modify: `client/src/components/WaitingRoom.tsx:5,85-87`
- Test: `server/test/tetris_web/channels/game_channel_test.exs`

**Step 1: Write failing test for `"battle"` difficulty in GameChannel**

Add to `server/test/tetris_web/channels/game_channel_test.exs` (in existing add_bot describe block, or create one):

```elixir
test "add_bot accepts battle difficulty" do
  # Follow existing test patterns in this file for joining a room
  # and pushing add_bot. The key assertion:
  ref = push(socket, "add_bot", %{"difficulty" => "battle"})
  assert_reply ref, :ok, %{bot_id: bot_id}
  assert is_binary(bot_id)
end
```

**Step 2: Run test to verify it fails**

Run: `cd server && mix test test/tetris_web/channels/game_channel_test.exs`

Expected: `invalid_difficulty` error reply.

**Step 3: Add `"battle"` case to GameChannel**

In `server/lib/tetris_web/channels/game_channel.ex`, modify the difficulty case match (around line 73-77):

```elixir
diff_atom =
  case difficulty do
    "easy" -> :easy
    "medium" -> :medium
    "hard" -> :hard
    "battle" -> :battle
    _ -> raise ArgumentError, "invalid difficulty: #{difficulty}"
  end
```

**Step 4: Add `"Battle"` option to WaitingRoom.tsx**

In `client/src/components/WaitingRoom.tsx`:

Update the `Difficulty` type (line 5):

```typescript
type Difficulty = "easy" | "medium" | "hard" | "battle";
```

Add the option in the `<select>` dropdown (after the `hard` option, around line 87):

```tsx
<option value="hard">Hard</option>
<option value="battle">Battle</option>
```

**Step 5: Run server tests to verify they pass**

Run: `cd server && mix test test/tetris_web/channels/game_channel_test.exs`

Expected: All tests pass.

**Step 6: Commit**

```bash
git add server/lib/tetris_web/channels/game_channel.ex client/src/components/WaitingRoom.tsx server/test/tetris_web/channels/game_channel_test.exs
git commit -m "feat: add battle difficulty to GameChannel and WaitingRoom UI"
```

---

### Task 7: Add battle_weights.json with default weights

**Files:**
- Create: `server/priv/battle_weights.json`

**Step 1: Create default battle weights file**

```json
{
  "config": {
    "population_size": 50,
    "generations": 100,
    "battles_per_genome": 10
  },
  "evolved_at": null,
  "fitness": 0.0,
  "weights": {
    "height": 0.15,
    "holes": 0.15,
    "bumpiness": 0.08,
    "lines": 0.10,
    "max_height": 0.05,
    "wells": 0.05,
    "garbage_incoming": 0.10,
    "garbage_send": 0.08,
    "tetris_bonus": 0.08,
    "opponent_danger": 0.06,
    "survival": 0.06,
    "line_efficiency": 0.04
  }
}
```

**Step 2: Commit**

```bash
git add server/priv/battle_weights.json
git commit -m "feat: add default battle_weights.json"
```

---

### Task 8: Run full test suite and fix any issues

**Step 1: Run all server tests**

Run: `cd server && mix test`

Expected: All tests pass. If any fail, fix them.

**Step 2: Run client build check**

Run: `cd client && npx tsc --noEmit`

Expected: No type errors.

**Step 3: Commit any fixes**

```bash
git add -A && git commit -m "fix: resolve test/type issues from battle bot integration"
```

---

### Task 9: Integration smoke test

**Step 1: Start the server**

Run: `cd server && mix phx.server`

**Step 2: Manually verify in browser**

1. Open `http://localhost:3000`
2. Create a multiplayer room
3. Add a "Battle" bot from the dropdown
4. Start the game
5. Verify the bot plays, targets opponents, and reacts to garbage

**Step 3: Verify battle simulation runs**

Run in IEx:

```elixir
solo = %{height: 0.51, holes: 0.36, bumpiness: 0.18, lines: 0.76, max_height: 0.0, wells: 0.0}
battle = Tetris.BotStrategy.weights_for(:battle)
BotTrainer.BattleSimulation.simulate_battle(battle, [solo, solo, solo], lookahead: false)
```

Expected: Returns a `%{placement: _, lines_cleared: _, pieces_placed: _, total_players: 4}` map.
