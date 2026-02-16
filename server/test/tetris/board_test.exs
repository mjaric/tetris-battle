defmodule Tetris.BoardTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.Piece

  describe "width/0" do
    test "returns 10" do
      assert Board.width() == 10
    end
  end

  describe "height/0" do
    test "returns 20" do
      assert Board.height() == 20
    end
  end

  describe "new/0" do
    test "creates a board with 20 rows" do
      board = Board.new()
      assert length(board) == 20
    end

    test "each row has 10 columns" do
      board = Board.new()

      for row <- board do
        assert length(row) == 10
      end
    end

    test "all cells are nil" do
      board = Board.new()

      for row <- board, cell <- row do
        assert cell == nil
      end
    end
  end

  describe "place_piece/4" do
    test "places a T piece at position" do
      board = Board.new()
      shape = Piece.new(:T).shape

      # T shape:
      # [0, 1, 0]
      # [1, 1, 1]
      # [0, 0, 0]
      new_board = Board.place_piece(board, shape, "#a000f0", {3, 0})

      # Row 0: cell at x=4 (3+1) should be colored
      assert Enum.at(Enum.at(new_board, 0), 4) == "#a000f0"
      # Row 1: cells at x=3,4,5 should be colored
      assert Enum.at(Enum.at(new_board, 1), 3) == "#a000f0"
      assert Enum.at(Enum.at(new_board, 1), 4) == "#a000f0"
      assert Enum.at(Enum.at(new_board, 1), 5) == "#a000f0"
      # Cells that are 0 in shape should remain nil
      assert Enum.at(Enum.at(new_board, 0), 3) == nil
      assert Enum.at(Enum.at(new_board, 0), 5) == nil
    end

    test "places an O piece at position" do
      board = Board.new()
      shape = Piece.new(:O).shape

      # O shape:
      # [1, 1]
      # [1, 1]
      new_board = Board.place_piece(board, shape, "#f0f000", {4, 0})

      assert Enum.at(Enum.at(new_board, 0), 4) == "#f0f000"
      assert Enum.at(Enum.at(new_board, 0), 5) == "#f0f000"
      assert Enum.at(Enum.at(new_board, 1), 4) == "#f0f000"
      assert Enum.at(Enum.at(new_board, 1), 5) == "#f0f000"
    end

    test "places piece at bottom of board" do
      board = Board.new()
      shape = Piece.new(:O).shape

      new_board = Board.place_piece(board, shape, "#f0f000", {0, 18})

      assert Enum.at(Enum.at(new_board, 18), 0) == "#f0f000"
      assert Enum.at(Enum.at(new_board, 18), 1) == "#f0f000"
      assert Enum.at(Enum.at(new_board, 19), 0) == "#f0f000"
      assert Enum.at(Enum.at(new_board, 19), 1) == "#f0f000"
    end

    test "does not overwrite existing cells (only places where shape is 1)" do
      board = Board.new()
      shape = Piece.new(:O).shape

      # Place one piece first
      board = Board.place_piece(board, shape, "#f0f000", {0, 0})
      # Place another piece nearby
      shape2 = Piece.new(:O).shape
      board = Board.place_piece(board, shape2, "#00f0f0", {2, 0})

      # Both pieces should be present
      assert Enum.at(Enum.at(board, 0), 0) == "#f0f000"
      assert Enum.at(Enum.at(board, 0), 2) == "#00f0f0"
    end
  end

  describe "valid_position?/3" do
    test "valid placement on empty board" do
      board = Board.new()
      shape = Piece.new(:T).shape

      assert Board.valid_position?(board, shape, {3, 5}) == true
    end

    test "valid placement at top-left corner" do
      board = Board.new()
      shape = Piece.new(:T).shape

      # T shape has 0 in top-left, so placing at {0, 0} is fine
      assert Board.valid_position?(board, shape, {0, 0}) == true
    end

    test "valid when y is negative (spawn above board)" do
      board = Board.new()
      # T shape:
      # [0, 1, 0]   <- row at y=-1 (above board, OK)
      # [1, 1, 1]   <- row at y=0
      # [0, 0, 0]   <- row at y=1
      shape = Piece.new(:T).shape

      assert Board.valid_position?(board, shape, {3, -1}) == true
    end

    test "out of bounds left" do
      board = Board.new()
      # T shape:
      # [0, 1, 0]
      # [1, 1, 1]  <- leftmost 1 is at shape col 0
      # [0, 0, 0]
      shape = Piece.new(:T).shape

      # Place at x=-1: the leftmost filled cell at shape col 0 would be at board x=-1
      assert Board.valid_position?(board, shape, {-1, 5}) == false
    end

    test "out of bounds right" do
      board = Board.new()
      shape = Piece.new(:T).shape

      # T shape is 3 wide, placing at x=8 means cells at 8,9,10 - 10 is out of bounds
      assert Board.valid_position?(board, shape, {8, 5}) == false
    end

    test "out of bounds bottom" do
      board = Board.new()
      shape = Piece.new(:T).shape

      # T shape is 3 tall (though bottom row is empty), placing at y=19
      # Row 1 of shape (the filled row [1,1,1]) is at board y=20, which is out of bounds
      assert Board.valid_position?(board, shape, {3, 19}) == false
    end

    test "overlapping with existing piece" do
      board = Board.new()
      shape = Piece.new(:O).shape

      # Place a piece first
      board = Board.place_piece(board, shape, "#f0f000", {3, 5})

      # Try to place another piece at the same position
      assert Board.valid_position?(board, shape, {3, 5}) == false
    end

    test "adjacent pieces do not overlap" do
      board = Board.new()
      shape = Piece.new(:O).shape

      # Place a piece
      board = Board.place_piece(board, shape, "#f0f000", {3, 5})

      # Place right next to it - should be valid
      assert Board.valid_position?(board, shape, {5, 5}) == true
    end
  end

  describe "clear_lines/1" do
    test "clears a single full line" do
      board = Board.new()

      # Fill the bottom row entirely
      board =
        List.replace_at(board, 19, List.duplicate("#808080", 10))

      {new_board, lines_cleared} = Board.clear_lines(board)

      assert lines_cleared == 1
      # Bottom row should now be empty (new row added at top)
      assert Enum.at(new_board, 19) == List.duplicate(nil, 10)
      # Top row should be the newly inserted empty row
      assert Enum.at(new_board, 0) == List.duplicate(nil, 10)
      assert length(new_board) == 20
    end

    test "clears multiple full lines" do
      board = Board.new()

      # Fill bottom two rows
      board =
        board
        |> List.replace_at(18, List.duplicate("#808080", 10))
        |> List.replace_at(19, List.duplicate("#ff0000", 10))

      {new_board, lines_cleared} = Board.clear_lines(board)

      assert lines_cleared == 2
      # Both bottom rows should now be empty
      assert Enum.at(new_board, 18) == List.duplicate(nil, 10)
      assert Enum.at(new_board, 19) == List.duplicate(nil, 10)
      assert length(new_board) == 20
    end

    test "no lines to clear" do
      board = Board.new()

      {new_board, lines_cleared} = Board.clear_lines(board)

      assert lines_cleared == 0
      assert new_board == board
    end

    test "does not clear partially filled line" do
      board = Board.new()

      # Fill bottom row with one gap
      row = List.duplicate("#808080", 9) ++ [nil]
      board = List.replace_at(board, 19, row)

      {new_board, lines_cleared} = Board.clear_lines(board)

      assert lines_cleared == 0
      assert new_board == board
    end

    test "preserves rows above cleared lines" do
      board = Board.new()

      # Place something on row 17
      board =
        List.update_at(board, 17, fn row ->
          List.replace_at(row, 0, "#00ff00")
        end)

      # Fill rows 18 and 19
      board =
        board
        |> List.replace_at(18, List.duplicate("#808080", 10))
        |> List.replace_at(19, List.duplicate("#808080", 10))

      {new_board, lines_cleared} = Board.clear_lines(board)

      assert lines_cleared == 2
      # Row 17 content should now be at row 19 (shifted down by 2)
      assert Enum.at(Enum.at(new_board, 19), 0) == "#00ff00"
    end
  end

  describe "add_garbage/2" do
    test "adds garbage rows at bottom, pushes existing rows up" do
      board = Board.new()

      # Place something on row 19 (bottom)
      board =
        List.update_at(board, 19, fn row ->
          List.replace_at(row, 5, "#ff0000")
        end)

      garbage_rows = [List.duplicate("#808080", 9) |> List.insert_at(3, nil)]

      {new_board, overflow} = Board.add_garbage(board, garbage_rows)

      assert overflow == false
      assert length(new_board) == 20
      # The old bottom row (19) should now be at row 18
      assert Enum.at(Enum.at(new_board, 18), 5) == "#ff0000"
      # Bottom row should be the garbage
      assert length(Enum.at(new_board, 19)) == 10
    end

    test "overflow detection when non-nil cell pushed off top" do
      board = Board.new()

      # Place something on row 0 (top)
      board =
        List.update_at(board, 0, fn row ->
          List.replace_at(row, 5, "#ff0000")
        end)

      # Add a garbage row - this pushes row 0 off the top
      garbage_rows = [List.duplicate("#808080", 9) |> List.insert_at(3, nil)]

      {new_board, overflow} = Board.add_garbage(board, garbage_rows)

      assert overflow == true
      assert length(new_board) == 20
    end

    test "no overflow when only nil cells pushed off top" do
      board = Board.new()

      # Top row is all nil, adding one garbage row is safe
      garbage_rows = [List.duplicate("#808080", 9) |> List.insert_at(3, nil)]

      {new_board, overflow} = Board.add_garbage(board, garbage_rows)

      assert overflow == false
      assert length(new_board) == 20
    end
  end

  describe "ghost_position/3" do
    test "drops to bottom on empty board" do
      board = Board.new()
      shape = Piece.new(:T).shape

      # T shape:
      # [0, 1, 0]
      # [1, 1, 1]
      # [0, 0, 0]
      # The lowest filled row of T is row 1 (index 1).
      # At position {3, y}, row 1 maps to board y+1.
      # For T to fit, y+1 must be <= 19, so y <= 18.
      # Row 2 is [0,0,0] — no filled cells, so it doesn't constrain.
      {px, lowest_y} = Board.ghost_position(board, shape, {3, 0})

      assert px == 3
      assert lowest_y == 18
    end

    test "stops at existing piece" do
      board = Board.new()

      # Place a row of blocks at row 15
      board =
        List.replace_at(board, 15, List.duplicate("#808080", 10))

      shape = Piece.new(:T).shape

      # T shape: filled cells in rows 0 and 1, row 2 is all zeros
      # At y=14: row 1 at board y=15 overlaps the filled row -> invalid
      # At y=13: row 0 at 13 (ok), row 1 at 14 (ok, empty), row 2 at 15 (all zeros, no check)
      {px, lowest_y} = Board.ghost_position(board, shape, {3, 0})

      assert px == 3
      assert lowest_y == 13
    end

    test "preserves x position" do
      board = Board.new()
      shape = Piece.new(:O).shape

      {px, _lowest_y} = Board.ghost_position(board, shape, {7, 0})

      assert px == 7
    end
  end

  describe "generate_garbage_row/0" do
    test "returns a row of length 10" do
      row = Board.generate_garbage_row()
      assert length(row) == 10
    end

    test "has exactly one nil gap" do
      row = Board.generate_garbage_row()
      nil_count = Enum.count(row, &is_nil/1)
      assert nil_count == 1
    end

    test "non-nil cells are #808080" do
      row = Board.generate_garbage_row()

      non_nil_cells = Enum.reject(row, &is_nil/1)
      assert length(non_nil_cells) == 9

      for cell <- non_nil_cells do
        assert cell == "#808080"
      end
    end
  end
end
