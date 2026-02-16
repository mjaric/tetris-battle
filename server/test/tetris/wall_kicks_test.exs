defmodule Tetris.WallKicksTest do
  use ExUnit.Case, async: true

  alias Tetris.WallKicks

  @normal_transitions [
    {0, 1},
    {1, 0},
    {1, 2},
    {2, 1},
    {2, 3},
    {3, 2},
    {3, 0},
    {0, 3}
  ]

  @normal_kick_data %{
    {0, 1} => [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}],
    {1, 0} => [{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}],
    {1, 2} => [{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}],
    {2, 1} => [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}],
    {2, 3} => [{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}],
    {3, 2} => [{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}],
    {3, 0} => [{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}],
    {0, 3} => [{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}]
  }

  @i_kick_data %{
    {0, 1} => [{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}],
    {1, 0} => [{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}],
    {1, 2} => [{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}],
    {2, 1} => [{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}],
    {2, 3} => [{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}],
    {3, 2} => [{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}],
    {3, 0} => [{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}],
    {0, 3} => [{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}]
  }

  describe "get/2 with normal pieces (T, S, Z, J, L)" do
    test "returns correct offsets for T piece rotation 0->1" do
      assert WallKicks.get(:T, {0, 1}) == [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}]
    end

    test "returns correct offsets for all normal piece transitions" do
      for type <- [:T, :S, :Z, :J, :L] do
        for transition <- @normal_transitions do
          expected = Map.fetch!(@normal_kick_data, transition)
          result = WallKicks.get(type, transition)

          assert result == expected,
                 "Expected #{inspect(expected)} for #{type} transition #{inspect(transition)}, got #{inspect(result)}"
        end
      end
    end

    test "each offset list has 5 entries for normal pieces" do
      for transition <- @normal_transitions do
        offsets = WallKicks.get(:T, transition)
        assert length(offsets) == 5, "Expected 5 offsets for transition #{inspect(transition)}"
      end
    end

    test "first offset is always {0, 0} for normal pieces" do
      for transition <- @normal_transitions do
        [{first_dx, first_dy} | _] = WallKicks.get(:T, transition)
        assert {first_dx, first_dy} == {0, 0}
      end
    end
  end

  describe "get/2 with I piece" do
    test "returns different offsets than normal pieces for I piece" do
      normal_offsets = WallKicks.get(:T, {0, 1})
      i_offsets = WallKicks.get(:I, {0, 1})

      assert normal_offsets != i_offsets
    end

    test "returns correct offsets for all I piece transitions" do
      for transition <- @normal_transitions do
        expected = Map.fetch!(@i_kick_data, transition)
        result = WallKicks.get(:I, transition)

        assert result == expected,
               "Expected #{inspect(expected)} for I transition #{inspect(transition)}, got #{inspect(result)}"
      end
    end

    test "each offset list has 5 entries for I piece" do
      for transition <- @normal_transitions do
        offsets = WallKicks.get(:I, transition)
        assert length(offsets) == 5, "Expected 5 offsets for I transition #{inspect(transition)}"
      end
    end

    test "first offset is always {0, 0} for I piece" do
      for transition <- @normal_transitions do
        [{first_dx, first_dy} | _] = WallKicks.get(:I, transition)
        assert {first_dx, first_dy} == {0, 0}
      end
    end
  end

  describe "get/2 with O piece" do
    test "returns [{0, 0}] for all transitions" do
      for transition <- @normal_transitions do
        assert WallKicks.get(:O, transition) == [{0, 0}],
               "O piece should return [{0, 0}] for transition #{inspect(transition)}"
      end
    end

    test "offset list has 1 entry for O piece" do
      offsets = WallKicks.get(:O, {0, 1})
      assert length(offsets) == 1
    end
  end

  describe "get/2 covers all 8 rotation transitions" do
    test "all 8 transitions are covered for normal pieces" do
      expected_transitions = [{0, 1}, {1, 0}, {1, 2}, {2, 1}, {2, 3}, {3, 2}, {3, 0}, {0, 3}]

      for transition <- expected_transitions do
        offsets = WallKicks.get(:T, transition)
        assert is_list(offsets)
        assert length(offsets) == 5
      end
    end

    test "all 8 transitions are covered for I piece" do
      expected_transitions = [{0, 1}, {1, 0}, {1, 2}, {2, 1}, {2, 3}, {3, 2}, {3, 0}, {0, 3}]

      for transition <- expected_transitions do
        offsets = WallKicks.get(:I, transition)
        assert is_list(offsets)
        assert length(offsets) == 5
      end
    end
  end
end
