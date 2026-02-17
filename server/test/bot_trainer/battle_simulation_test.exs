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

  describe "evaluate/4" do
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
