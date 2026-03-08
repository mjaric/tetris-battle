defmodule TetrisGpt.Training.BenchmarkSimulationTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Strategies.Heuristic
  alias TetrisGpt.Training.BenchmarkSimulation

  describe "run_game/3" do
    test "completes a game with heuristic strategy as GPT player" do
      # Use Heuristic as a stand-in for DecoderOnly (faster, no model init)
      state = Heuristic.init(difficulty: :hard)

      result =
        BenchmarkSimulation.run_game(
          Heuristic,
          state,
          difficulty: :hard
        )

      assert is_map(result)
      assert result.winner in 0..3
      assert is_boolean(result.gpt_won)
      assert map_size(result.stats) == 4

      gpt_stats = result.stats[0]
      assert gpt_stats.is_gpt == true
      assert gpt_stats.pieces_placed > 0
    end
  end

  describe "run_benchmark/3" do
    test "runs multiple games and returns summary" do
      state = Heuristic.init(difficulty: :hard)

      summary =
        BenchmarkSimulation.run_benchmark(
          Heuristic,
          state,
          num_games: 2,
          difficulty: :hard
        )

      assert summary.games == 2
      assert summary.gpt_wins >= 0
      assert summary.gpt_wins <= 2
      assert summary.win_rate >= 0.0
      assert summary.win_rate <= 1.0
      assert summary.avg_gpt_lines >= 0.0
      assert summary.avg_gpt_pieces >= 0.0
      assert length(summary.results) == 2
    end
  end
end
