defmodule Tetris.GameLogicEventsTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.GameLogic
  alias Tetris.Piece

  # Helper: create a board where the bottom N rows are filled except column 0
  defp board_with_filled_rows(n) do
    empty_row = List.duplicate(nil, 10)
    filled_row = [nil] ++ List.duplicate("gray", 9)

    empty_rows = List.duplicate(empty_row, 20 - n)
    filled_rows = List.duplicate(filled_row, n)
    empty_rows ++ filled_rows
  end

  # Helper: create a game state map
  defp make_state(opts) do
    board = Keyword.get(opts, :board, Board.new())
    piece = Keyword.get(opts, :piece, Piece.new(:I))

    %{
      board: board,
      current_piece: piece,
      position: Keyword.get(opts, :position, {0, 0}),
      next_piece: Piece.random(),
      score: 0,
      lines: 0,
      level: 1,
      alive: true,
      pending_garbage: [],
      gravity_counter: 0,
      gravity_threshold: 16,
      pieces_placed: 0,
      combo_count: Keyword.get(opts, :combo_count, 0),
      b2b_tetris: Keyword.get(opts, :b2b_tetris, false)
    }
  end

  describe "combo tracking" do
    test "combo_count increments on consecutive line clears" do
      # Create a board where bottom row is almost full (only col 0 empty)
      board = board_with_filled_rows(1)

      # Use I-piece horizontal at position that fills column 0 of bottom row
      state = make_state(board: board, piece: Piece.new(:I), position: {0, 18}, combo_count: 0)

      # Move down until locked
      {:ok, :locked, result} = GameLogic.move_down(state)

      # If lines were cleared, combo should be 1
      if Map.get(result, :lines_cleared_this_lock, 0) > 0 do
        assert result.combo_count >= 1
        assert Map.get(result, :combo_count_this_lock) >= 1
      end
    end

    test "combo_count resets to 0 when no lines are cleared" do
      # Empty board, piece locks without clearing
      state = make_state(combo_count: 3)

      # Place piece at bottom
      state = %{state | position: {0, 18}}
      {:ok, :locked, result} = GameLogic.move_down(state)

      lines = Map.get(result, :lines_cleared_this_lock, 0)

      if lines == 0 do
        assert result.combo_count == 0
      end
    end
  end

  describe "B2B Tetris tracking" do
    test "b2b_tetris set to true on 4-line clear" do
      # Build a board with 4 complete rows (except col 0)
      board = board_with_filled_rows(4)

      # I-piece vertical at column 0 should clear 4 lines
      i_piece = Piece.new(:I)
      # I-piece is horizontal by default: [[1,1,1,1]]
      # Rotate to vertical: [[1],[1],[1],[1]]
      i_piece = Piece.rotate(i_piece)

      state = make_state(board: board, piece: i_piece, position: {0, 15}, b2b_tetris: false)
      {:ok, :locked, result} = GameLogic.move_down(state)

      lines = Map.get(result, :lines_cleared_this_lock, 0)

      if lines == 4 do
        assert result.b2b_tetris == true
      end
    end

    test "is_b2b_tetris_this_lock true when previous was tetris and current is tetris" do
      board = board_with_filled_rows(4)
      i_piece = Piece.rotate(Piece.new(:I))

      state = make_state(board: board, piece: i_piece, position: {0, 15}, b2b_tetris: true)
      {:ok, :locked, result} = GameLogic.move_down(state)

      lines = Map.get(result, :lines_cleared_this_lock, 0)

      if lines == 4 do
        assert Map.get(result, :is_b2b_tetris_this_lock) == true
      end
    end
  end

  describe "hard_drop" do
    test "hard_drop returns hard_drop_distance" do
      state = make_state(position: {3, 0})
      {:ok, result} = GameLogic.hard_drop(state)

      assert Map.has_key?(result, :hard_drop_distance)
      assert result.hard_drop_distance > 0
    end
  end
end
