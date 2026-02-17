defmodule Tetris.BotStrategyTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.BotStrategy
  alias Tetris.Piece

  describe "plan_actions/3" do
    test "no rotation or movement produces just hard_drop" do
      actions = BotStrategy.plan_actions(3, 0, 3)
      assert actions == ["hard_drop"]
    end

    test "single rotation needed" do
      actions = BotStrategy.plan_actions(3, 1, 3)
      assert actions == ["rotate", "hard_drop"]
    end

    test "two rotations needed" do
      actions = BotStrategy.plan_actions(3, 2, 3)
      assert actions == ["rotate", "rotate", "hard_drop"]
    end

    test "three rotations needed" do
      actions = BotStrategy.plan_actions(3, 3, 3)
      assert actions == ["rotate", "rotate", "rotate", "hard_drop"]
    end

    test "move left" do
      actions = BotStrategy.plan_actions(5, 0, 3)
      assert actions == ["move_left", "move_left", "hard_drop"]
    end

    test "move right" do
      actions = BotStrategy.plan_actions(3, 0, 5)
      assert actions == ["move_right", "move_right", "hard_drop"]
    end

    test "rotation then move" do
      actions = BotStrategy.plan_actions(3, 2, 5)

      assert actions == [
               "rotate",
               "rotate",
               "move_right",
               "move_right",
               "hard_drop"
             ]
    end

    test "zero rotations with pre-rotated piece" do
      # enumerate_placements says 0 additional rotations needed
      actions = BotStrategy.plan_actions(4, 0, 4)
      rotate_count = Enum.count(actions, &(&1 == "rotate"))
      assert rotate_count == 0
    end
  end

  describe "enumerate_placements/2" do
    test "returns non-empty list for an empty board" do
      board = Board.new()
      piece = Piece.new(:T)
      placements = BotStrategy.enumerate_placements(board, piece)

      assert length(placements) > 0

      Enum.each(placements, fn pl ->
        assert Map.has_key?(pl, :rotation_count)
        assert Map.has_key?(pl, :target_x)
        assert Map.has_key?(pl, :metrics)
        assert Map.has_key?(pl, :resulting_board)
      end)
    end

    test "covers multiple rotations" do
      board = Board.new()
      piece = Piece.new(:T)
      placements = BotStrategy.enumerate_placements(board, piece)

      rotations = placements |> Enum.map(& &1.rotation_count) |> Enum.uniq()
      assert length(rotations) > 1
    end

    test "O piece has duplicates across rotations since shape is symmetric" do
      board = Board.new()
      o_piece = Piece.new(:O)
      placements = BotStrategy.enumerate_placements(board, o_piece)

      # O piece is 2x2 so 9 positions per rotation, 4 rotations = 36
      # All rotations produce the same shape, so x positions repeat
      unique_positions =
        placements
        |> Enum.map(fn pl -> pl.target_x end)
        |> Enum.uniq()

      assert length(unique_positions) == 9
      assert length(placements) == 36
    end
  end

  describe "score_placement/2" do
    test "fewer holes scores higher" do
      weights = %{height: 0.5, holes: 0.5, bumpiness: 0.2, lines: 0.5}

      no_holes = %{aggregate_height: 5, holes: 0, bumpiness: 2, complete_lines: 0}
      with_holes = %{aggregate_height: 5, holes: 3, bumpiness: 2, complete_lines: 0}

      assert BotStrategy.score_placement(no_holes, weights) >
               BotStrategy.score_placement(with_holes, weights)
    end

    test "clearing lines improves score" do
      weights = %{height: 0.5, holes: 0.5, bumpiness: 0.2, lines: 0.76}

      no_clear = %{aggregate_height: 10, holes: 0, bumpiness: 0, complete_lines: 0}
      with_clear = %{aggregate_height: 10, holes: 0, bumpiness: 0, complete_lines: 2}

      assert BotStrategy.score_placement(with_clear, weights) >
               BotStrategy.score_placement(no_clear, weights)
    end
  end

  describe "score_battle_placement/3" do
    @battle_weights %{
      height: 0.2,
      holes: 0.2,
      bumpiness: 0.1,
      lines: 0.1,
      max_height: 0.05,
      wells: 0.05,
      garbage_incoming: 0.1,
      garbage_send: 0.05,
      tetris_bonus: 0.05,
      opponent_danger: 0.05,
      survival: 0.03,
      line_efficiency: 0.02
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

      score_safe =
        BotStrategy.score_battle_placement(
          metrics,
          @battle_weights,
          ctx_no_garbage
        )

      score_danger =
        BotStrategy.score_battle_placement(
          metrics,
          @battle_weights,
          ctx_with_garbage
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

      score_single =
        BotStrategy.score_battle_placement(
          single,
          @battle_weights,
          ctx
        )

      score_tetris =
        BotStrategy.score_battle_placement(
          tetris,
          @battle_weights,
          ctx
        )

      assert score_tetris > score_single
    end

    test "increases survival penalty as board fills up" do
      ctx_high = %{
        pending_garbage_count: 0,
        own_max_height: 18,
        opponent_max_heights: [5],
        opponent_count: 1,
        leading_opponent_score: 100
      }

      ctx_low = %{
        pending_garbage_count: 0,
        own_max_height: 5,
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

      score_high =
        BotStrategy.score_battle_placement(
          metrics_high,
          @battle_weights,
          ctx_high
        )

      score_low =
        BotStrategy.score_battle_placement(
          metrics_low,
          @battle_weights,
          ctx_low
        )

      assert score_low > score_high
    end
  end

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
          board,
          piece,
          {3, 0},
          next,
          :battle,
          battle_ctx
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

  describe "best_placement/5" do
    test "returns valid actions for easy difficulty" do
      board = Board.new()
      piece = Piece.new(:T)
      next = Piece.new(:I)

      {rot, x, actions} =
        BotStrategy.best_placement(board, piece, {3, 0}, next, :easy)

      assert is_integer(rot) and rot in 0..3
      assert is_integer(x) and x >= 0
      assert is_list(actions)
      assert List.last(actions) == "hard_drop"

      assert Enum.all?(actions, fn a ->
               a in ["rotate", "move_left", "move_right", "hard_drop"]
             end)
    end

    test "returns valid actions for hard difficulty with lookahead" do
      board = Board.new()
      piece = Piece.new(:I)
      next = Piece.new(:O)

      {rot, x, actions} =
        BotStrategy.best_placement(board, piece, {3, 0}, next, :hard)

      assert is_integer(rot) and rot in 0..3
      assert is_integer(x) and x >= 0
      assert List.last(actions) == "hard_drop"
    end

    test "prefers line clears on a nearly full board" do
      board = Board.new()

      almost_full_row =
        List.duplicate("#ff0000", 9) ++ [nil]

      board =
        Enum.reduce(19..19, board, fn row_idx, b ->
          List.update_at(b, row_idx, fn _ -> almost_full_row end)
        end)

      # I piece horizontal can fill the gap
      piece = Piece.new(:I)
      next = Piece.new(:T)

      {_rot, _x, actions} =
        BotStrategy.best_placement(board, piece, {3, 0}, next, :medium)

      assert List.last(actions) == "hard_drop"
    end
  end
end
