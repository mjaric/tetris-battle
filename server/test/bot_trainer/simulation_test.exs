defmodule BotTrainer.SimulationTest do
  use ExUnit.Case, async: true

  alias BotTrainer.Simulation

  @good_weights %{
    height: 0.51, holes: 0.36, bumpiness: 0.18,
    lines: 0.76, max_height: 0.0, wells: 0.0
  }

  # Tests use lookahead: false for speed.
  # Evolution runs use lookahead: true (default).

  describe "play_game/2" do
    test "completes a game and returns valid result" do
      result = Simulation.play_game(@good_weights, lookahead: false)

      assert is_integer(result.lines_cleared)
      assert result.lines_cleared >= 0
      assert is_integer(result.score)
      assert result.score >= 0
      assert is_integer(result.pieces_placed)
      assert result.pieces_placed > 0
    end

    test "terminates with zero weights" do
      weights = %{
        height: 0.0, holes: 0.0, bumpiness: 0.0,
        lines: 0.0, max_height: 0.0, wells: 0.0
      }

      result = Simulation.play_game(weights, lookahead: false)

      assert is_integer(result.lines_cleared)
      assert result.pieces_placed > 0
    end

    test "better weights tend to outperform bad weights" do
      bad = %{
        height: 0.0, holes: 0.0, bumpiness: 0.0,
        lines: 1.0, max_height: 0.0, wells: 0.0
      }

      good_avg = Simulation.evaluate(@good_weights, 5, lookahead: false)
      bad_avg = Simulation.evaluate(bad, 5, lookahead: false)

      assert good_avg > bad_avg
    end
  end

  describe "evaluate/3" do
    test "returns a float average" do
      avg = Simulation.evaluate(@good_weights, 3, lookahead: false)

      assert is_float(avg)
      assert avg >= 0.0
    end
  end
end
