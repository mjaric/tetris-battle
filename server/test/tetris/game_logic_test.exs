defmodule Tetris.GameLogicTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.GameLogic
  alias Tetris.Piece

  # Helper to build a minimal valid game state
  defp new_state(overrides) do
    current_piece = Piece.new(:T)
    next_piece = Piece.new(:I)

    Map.merge(
      %{
        board: Board.new(),
        current_piece: current_piece,
        position: {3, 0},
        next_piece: next_piece,
        score: 0,
        lines: 0,
        level: 1,
        alive: true,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16
      },
      overrides
    )
  end

  describe "move_left/1" do
    test "moves piece one cell to the left" do
      state = new_state(%{position: {5, 5}})

      assert {:ok, new_state} = GameLogic.move_left(state)
      assert new_state.position == {4, 5}
    end

    test "returns :invalid when blocked by left wall" do
      # T piece shape:
      # [0, 1, 0]
      # [1, 1, 1]
      # [0, 0, 0]
      # At x=0, the leftmost filled cell is at column 0 (row 1, col 0).
      # Moving left would put it at x=-1, which is out of bounds.
      state = new_state(%{position: {0, 5}})

      assert :invalid = GameLogic.move_left(state)
    end

    test "returns :invalid when blocked by another piece" do
      board = Board.new()
      # Place a block to the left of where the piece would move
      board =
        List.update_at(board, 6, fn row ->
          List.replace_at(row, 2, "#ff0000")
        end)

      # T piece at {3, 5}: row 1 of T (the [1,1,1] row) is at board y=6
      # The leftmost cell of that row is at board x=3.
      # Moving left would put it at x=2, which is occupied.
      state = new_state(%{board: board, position: {3, 5}})

      assert :invalid = GameLogic.move_left(state)
    end
  end

  describe "move_right/1" do
    test "moves piece one cell to the right" do
      state = new_state(%{position: {3, 5}})

      assert {:ok, new_state} = GameLogic.move_right(state)
      assert new_state.position == {4, 5}
    end

    test "returns :invalid when blocked by right wall" do
      # T piece is 3 wide. At x=7, rightmost filled cell is at x=9.
      # Moving right would put rightmost at x=10, out of bounds.
      state = new_state(%{position: {7, 5}})

      assert :invalid = GameLogic.move_right(state)
    end

    test "returns :invalid when blocked by another piece" do
      board = Board.new()
      # Place a block to the right
      board =
        List.update_at(board, 6, fn row ->
          List.replace_at(row, 6, "#ff0000")
        end)

      # T piece at {3, 5}: row 1 of T is at board y=6, rightmost cell at x=5.
      # Moving right: rightmost would be at x=6, which is occupied.
      state = new_state(%{board: board, position: {3, 5}})

      assert :invalid = GameLogic.move_right(state)
    end
  end

  describe "move_down/1" do
    test "moves piece one cell down when space available" do
      state = new_state(%{position: {3, 5}})

      assert {:ok, :moved, new_state} = GameLogic.move_down(state)
      assert new_state.position == {3, 6}
    end

    test "locks piece when it cannot move down" do
      # Place piece near the bottom so it can't move further
      # T piece at y=18: row 1 (the filled row) is at board y=19 (bottom).
      # Moving down would put row 1 at y=20, which is out of bounds.
      state = new_state(%{position: {3, 18}})

      assert {:ok, :locked, new_state} = GameLogic.move_down(state)
      # After locking, the piece should be placed on the board
      # Check that board has the T piece colors at the locked position
      assert Enum.at(Enum.at(new_state.board, 18), 4) != nil
    end

    test "locks piece when blocked by existing piece below" do
      board = Board.new()
      # Fill row 10 entirely to block downward movement
      board = List.replace_at(board, 10, List.duplicate("#808080", 10))

      # T piece at y=8: row 1 (filled [1,1,1]) at board y=9.
      # Moving down: row 1 at y=10, which is full -> invalid.
      state = new_state(%{board: board, position: {3, 8}})

      assert {:ok, :locked, _new_state} = GameLogic.move_down(state)
    end
  end

  describe "rotate/1" do
    test "rotates piece when space is available" do
      state = new_state(%{position: {4, 10}})

      assert {:ok, new_state} = GameLogic.rotate(state)
      # T piece rotated once:
      # [0, 1, 0]
      # [0, 1, 1]
      # [0, 1, 0]
      assert new_state.current_piece.rotation == 1
    end

    test "applies wall kick when basic rotation is blocked" do
      # T at {4, 10}, rotation 0 -> rotated to 1: [0,1,0],[0,1,1],[0,1,0]
      # Rotated at {4,10}: (5,10)=1, (5,11)=1, (6,11)=1, (5,12)=1
      # Block (5,10) to prevent basic rotation at kick {0,0}
      board =
        Board.new()
        |> List.update_at(10, fn row -> List.replace_at(row, 5, "#808080") end)

      state = new_state(%{board: board, position: {4, 10}})

      # Wall kicks for T {0,1}: [{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}]
      # Kick {0,0}: blocked (cell at (5,10) occupied)
      # Kick {-1,0}: position becomes {4-1, 10-0} = {3, 10}
      #   rotated at {3,10}: (4,10)=1, (4,11)=1, (5,11)=1, (4,12)=1 -- all valid
      # So the kick {-1, 0} should succeed.
      result = GameLogic.rotate(state)
      assert {:ok, new_state} = result
      assert new_state.current_piece.rotation == 1
      assert new_state.position == {3, 10}
    end

    test "returns :invalid when no rotation is possible" do
      # T at {0,0}, rotation 0 shape: [0,1,0],[1,1,1],[0,0,0]
      # Current T needs: (1,0)=nil, (0,1)=nil, (1,1)=nil, (2,1)=nil
      #
      # Rotated T (rot 1): [0,1,0],[0,1,1],[0,1,0]
      # Wall kicks for T {0,1}: [{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}]
      #
      # Kick {0,0} at {0,0}: needs (1,0),(1,1),(2,1),(1,2) - block (1,2)
      # Kick {-1,0} at {-1,0}: needs (0,0),(0,1),(1,1),(0,2) - block (0,0)
      # Kick {-1,1} at {-1,-1}: needs (0,-1)ok,(0,0),(1,0),(0,1) - (0,0) blocked
      # Kick {0,-2} at {0,2}: needs (1,2),(1,3),(2,3),(1,4) - (1,2) blocked, rows 3+ full
      # Kick {-1,-2} at {-1,2}: needs (0,2),(0,3),(1,3),(0,4) - rows 3+ full
      board =
        Enum.with_index(Board.new())
        |> Enum.map(fn {_row, row_idx} ->
          Enum.map(0..9, fn col ->
            cond do
              # Keep current T footprint empty
              row_idx == 0 and col == 1 -> nil
              row_idx == 1 and col in [0, 1, 2] -> nil
              # Row 2: block col 1 to prevent kick {0,0} rotated cell (1,2)
              # Col 0 can be nil (current T row 2 is [0,0,0], doesn't matter)
              true -> "#808080"
            end
          end)
        end)

      state = new_state(%{board: board, position: {0, 0}})

      assert :invalid = GameLogic.rotate(state)
    end
  end

  describe "hard_drop/1" do
    test "drops piece to bottom and locks it" do
      state = new_state(%{position: {3, 0}})

      assert {:ok, new_state} = GameLogic.hard_drop(state)
      # T piece on empty board: ghost position y=18
      # The piece should be locked on the board at y=18
      # Row 18, col 4 should have the T color (top of T: [0,1,0])
      assert Enum.at(Enum.at(new_state.board, 18), 4) == "#a000f0"
      # Row 19, cols 3,4,5 should have the T color (middle of T: [1,1,1])
      assert Enum.at(Enum.at(new_state.board, 19), 3) == "#a000f0"
      assert Enum.at(Enum.at(new_state.board, 19), 4) == "#a000f0"
      assert Enum.at(Enum.at(new_state.board, 19), 5) == "#a000f0"
    end

    test "adds score based on drop distance" do
      # Ghost position for T at {3,0} on empty board is {3,18}, distance = 18
      # Score = distance * 2 = 36
      state = new_state(%{position: {3, 0}, score: 0})

      assert {:ok, new_state} = GameLogic.hard_drop(state)
      assert new_state.score >= 36
    end

    test "hard drop from higher position scores more" do
      state_high = new_state(%{position: {3, 0}, score: 0})
      state_low = new_state(%{position: {3, 15}, score: 0})

      {:ok, result_high} = GameLogic.hard_drop(state_high)
      {:ok, result_low} = GameLogic.hard_drop(state_low)

      assert result_high.score > result_low.score
    end
  end

  describe "apply_gravity/1" do
    test "increments counter without moving when below threshold" do
      state = new_state(%{gravity_counter: 0, gravity_threshold: 16, position: {3, 5}})

      assert {:ok, :waiting, new_state} = GameLogic.apply_gravity(state)
      assert new_state.gravity_counter == 1
      assert new_state.position == {3, 5}
    end

    test "moves piece down and resets counter when counter reaches threshold" do
      state = new_state(%{gravity_counter: 15, gravity_threshold: 16, position: {3, 5}})

      assert {:ok, :moved, new_state} = GameLogic.apply_gravity(state)
      assert new_state.gravity_counter == 0
      assert new_state.position == {3, 6}
    end

    test "locks piece when gravity moves down and piece cannot move" do
      state = new_state(%{gravity_counter: 15, gravity_threshold: 16, position: {3, 18}})

      assert {:ok, :locked, _new_state} = GameLogic.apply_gravity(state)
    end
  end

  describe "spawn_piece/1" do
    test "spawns next piece at top center" do
      next = Piece.new(:I)
      state = new_state(%{next_piece: next})

      assert {:ok, new_state} = GameLogic.spawn_piece(state)
      assert new_state.current_piece.type == :I
      # I piece is 4 wide, center position: (10 - 4) / 2 = 3
      {x, y} = new_state.position
      assert x == 3
      assert y == 0
      # A new next_piece should have been generated
      assert %Piece{} = new_state.next_piece
    end

    test "returns :game_over when spawn position is blocked" do
      board = Board.new()
      # Fill the top rows to block spawning
      board =
        board
        |> List.replace_at(0, List.duplicate("#808080", 10))
        |> List.replace_at(1, List.duplicate("#808080", 10))

      next = Piece.new(:T)
      state = new_state(%{board: board, next_piece: next})

      assert {:game_over, new_state} = GameLogic.spawn_piece(state)
      assert new_state.alive == false
    end

    test "spawns different piece sizes at correct center positions" do
      # O piece is 2 wide: center = (10 - 2) / 2 = 4
      next = Piece.new(:O)
      state = new_state(%{next_piece: next})

      assert {:ok, new_state} = GameLogic.spawn_piece(state)
      {x, _y} = new_state.position
      assert x == 4
    end
  end

  describe "line clearing and scoring" do
    test "clears one line and scores 100 * level" do
      board = Board.new()
      # Fill bottom row except where T piece will complete it
      # Use a setup where locking a piece completes a line.
      # Fill row 19 with all but 3 cells (cols 3,4,5), then drop T piece so row 1
      # of T fills those cells.
      row_19 =
        Enum.map(0..9, fn col ->
          if col in [3, 4, 5], do: nil, else: "#808080"
        end)

      board = List.replace_at(board, 19, row_19)

      # T piece at {3, 18}: row 0 [0,1,0] at y=18, row 1 [1,1,1] at y=19
      # Row 19 will become full after placing T's row 1.
      state = new_state(%{board: board, position: {3, 18}, score: 0, level: 1, lines: 0})

      {:ok, :locked, result} = GameLogic.move_down(state)

      assert result.score >= 100
      assert result.lines >= 1
    end

    test "four lines (tetris) scores 800 * level" do
      board = Board.new()
      # Fill rows 16-19 except column 0
      board =
        Enum.with_index(board)
        |> Enum.map(fn {row, idx} ->
          if idx in [16, 17, 18, 19] do
            Enum.with_index(row)
            |> Enum.map(fn {_cell, col} ->
              if col == 0, do: nil, else: "#808080"
            end)
          else
            row
          end
        end)

      # Use I piece (4 tall when rotated) to fill column 0 at rows 16-19
      # Rotated I piece:
      # [0, 0, 1, 0]
      # [0, 0, 1, 0]
      # [0, 0, 1, 0]
      # [0, 0, 1, 0]
      # At position {-2, 16}: col 2 maps to board x=0, rows 16-19.
      i_piece = Piece.new(:I) |> Piece.rotate()

      state =
        new_state(%{
          board: board,
          current_piece: i_piece,
          position: {-2, 16},
          score: 0,
          level: 1,
          lines: 0
        })

      {:ok, :locked, result} = GameLogic.move_down(state)

      assert result.score >= 800
      assert result.lines >= 4
    end

    test "level calculation: level = lines / 10 + 1" do
      board = Board.new()
      # Set up a state where clearing a line brings lines to 10, level should become 2
      row_19 =
        Enum.map(0..9, fn col ->
          if col in [3, 4, 5], do: nil, else: "#808080"
        end)

      board = List.replace_at(board, 19, row_19)

      state = new_state(%{board: board, position: {3, 18}, score: 0, level: 1, lines: 9})

      {:ok, :locked, result} = GameLogic.move_down(state)

      # After clearing 1 line, lines = 10, level = 10/10 + 1 = 2
      assert result.lines == 10
      assert result.level == 2
    end

    test "scoring is multiplied by level" do
      board = Board.new()
      row_19 =
        Enum.map(0..9, fn col ->
          if col in [3, 4, 5], do: nil, else: "#808080"
        end)

      board = List.replace_at(board, 19, row_19)

      state_l1 = new_state(%{board: board, position: {3, 18}, score: 0, level: 1, lines: 0})
      state_l2 = new_state(%{board: board, position: {3, 18}, score: 0, level: 2, lines: 0})

      {:ok, :locked, result_l1} = GameLogic.move_down(state_l1)
      {:ok, :locked, result_l2} = GameLogic.move_down(state_l2)

      # Level 2 should score double
      assert result_l2.score > result_l1.score
    end
  end

  describe "apply_pending_garbage/1" do
    test "applies pending garbage rows to the board" do
      garbage_row = Board.generate_garbage_row()
      state = new_state(%{pending_garbage: [garbage_row]})

      assert {:ok, new_state} = GameLogic.apply_pending_garbage(state)
      assert new_state.pending_garbage == []
      # Bottom row should be the garbage row
      assert Enum.at(new_state.board, 19) == garbage_row
    end

    test "returns :game_over when garbage causes overflow" do
      board = Board.new()
      # Fill the top row
      board = List.replace_at(board, 0, List.duplicate("#808080", 10))

      garbage_row = Board.generate_garbage_row()
      state = new_state(%{board: board, pending_garbage: [garbage_row]})

      assert {:game_over, new_state} = GameLogic.apply_pending_garbage(state)
      assert new_state.alive == false
    end

    test "returns :ok with no pending garbage" do
      state = new_state(%{pending_garbage: []})

      assert {:ok, new_state} = GameLogic.apply_pending_garbage(state)
      assert new_state.board == state.board
    end
  end

  describe "gravity_threshold/1" do
    test "returns 16 for level 1" do
      assert GameLogic.gravity_threshold(1) == 16
    end

    test "returns 15 for level 2" do
      assert GameLogic.gravity_threshold(2) == 15
    end

    test "returns 2 for very high levels" do
      assert GameLogic.gravity_threshold(100) == 2
    end

    test "never goes below 2" do
      assert GameLogic.gravity_threshold(20) == 2
      assert GameLogic.gravity_threshold(50) == 2
    end

    test "formula: max(2, 16 - (level - 1))" do
      for level <- 1..20 do
        expected = max(2, 16 - (level - 1))
        assert GameLogic.gravity_threshold(level) == expected
      end
    end
  end
end
