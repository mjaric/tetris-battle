defmodule TetrisGpt.Strategies.HeuristicTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Strategies.Heuristic

  test "implements Strategy behaviour and returns valid placements" do
    state = Heuristic.init(difficulty: :hard)
    assert Heuristic.name() == "heuristic"

    context = %{
      board: List.duplicate(List.duplicate(nil, 10), 20),
      current_piece: :T,
      next_piece: :I,
      battle_context: %{
        pending_garbage_count: 0,
        own_max_height: 0,
        opponent_max_height: 0,
        combo_count: 0,
        lines: 0,
        score_diff: 0,
        opponent_count: 3,
        alive: true
      }
    }

    {placement, _new_state} = Heuristic.predict(state, context)
    assert placement.rotation in 0..3
    assert placement.column in 0..9
  end
end
