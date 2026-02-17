defmodule Tetris.PlayerStateTest do
  use ExUnit.Case, async: true

  alias Tetris.PlayerState
  alias Tetris.Board
  alias Tetris.Piece

  describe "new/2" do
    test "creates a valid state with correct defaults" do
      state = PlayerState.new("player-1", "Alice")

      assert state.player_id == "player-1"
      assert state.nickname == "Alice"
      assert state.score == 0
      assert state.lines == 0
      assert state.level == 1
      assert state.alive == true
      assert state.target == nil
      assert state.pending_garbage == []
      assert state.gravity_counter == 0
      assert state.gravity_threshold == 16
      assert state.input_queue == :queue.new()
    end

    test "initializes board as empty 20x10 grid" do
      state = PlayerState.new("player-1", "Alice")

      assert state.board == Board.new()
    end

    test "initializes current_piece as a valid piece" do
      state = PlayerState.new("player-1", "Alice")

      assert %Piece{} = state.current_piece
      assert state.current_piece.type in Piece.types()
      assert state.current_piece.rotation == 0
    end

    test "initializes next_piece as a valid piece" do
      state = PlayerState.new("player-1", "Alice")

      assert %Piece{} = state.next_piece
      assert state.next_piece.type in Piece.types()
      assert state.next_piece.rotation == 0
    end

    test "position is centered horizontally based on piece width" do
      # Use a known piece to verify the centering formula
      state = PlayerState.new("player-1", "Alice")

      piece = state.current_piece
      piece_width = length(hd(piece.shape))
      expected_x = div(Board.width() - piece_width, 2)

      {x, y} = state.position
      assert x == expected_x
      assert y == -1
    end

    test "position y is -1 (spawns above the board)" do
      state = PlayerState.new("player-1", "Alice")

      {_x, y} = state.position
      assert y == -1
    end
  end

  describe "to_broadcast/1" do
    test "returns correct map structure" do
      state = PlayerState.new("player-1", "Alice")
      broadcast = PlayerState.to_broadcast(state)

      assert is_map(broadcast)
      assert broadcast.nickname == "Alice"
      assert is_integer(broadcast.score)
      assert broadcast.score == 0
      assert is_integer(broadcast.lines)
      assert broadcast.lines == 0
      assert is_integer(broadcast.level)
      assert broadcast.level == 1
      assert broadcast.alive == true
      assert is_binary(broadcast.next_piece)
      assert broadcast.target == nil
    end

    test "next_piece is the type as a string" do
      state = PlayerState.new("player-1", "Alice")
      broadcast = PlayerState.to_broadcast(state)

      # The next_piece should be the atom type converted to string
      assert broadcast.next_piece == Atom.to_string(state.next_piece.type)
    end

    test "board is a 20x10 list of lists" do
      state = PlayerState.new("player-1", "Alice")
      broadcast = PlayerState.to_broadcast(state)

      assert is_list(broadcast.board)
      assert length(broadcast.board) == 20

      for row <- broadcast.board do
        assert length(row) == 10
      end
    end

    test "includes composited current piece in board" do
      # Create a state with a known T piece at a known position
      piece = Piece.new(:T)
      state = %PlayerState{
        player_id: "player-1",
        nickname: "Alice",
        board: Board.new(),
        current_piece: piece,
        position: {3, 5},
        next_piece: Piece.new(:O),
        score: 0,
        lines: 0,
        level: 1,
        alive: true,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        input_queue: :queue.new()
      }

      broadcast = PlayerState.to_broadcast(state)

      # T shape at {3, 5}:
      # Row 5: [0, 1, 0] -> cell (4, 5) is colored
      # Row 6: [1, 1, 1] -> cells (3, 6), (4, 6), (5, 6) are colored
      # Row 7: [0, 0, 0] -> no cells colored
      assert Enum.at(Enum.at(broadcast.board, 5), 4) == piece.color
      assert Enum.at(Enum.at(broadcast.board, 6), 3) == piece.color
      assert Enum.at(Enum.at(broadcast.board, 6), 4) == piece.color
      assert Enum.at(Enum.at(broadcast.board, 6), 5) == piece.color
    end

    test "includes ghost piece in board" do
      piece = Piece.new(:T)
      state = %PlayerState{
        player_id: "player-1",
        nickname: "Alice",
        board: Board.new(),
        current_piece: piece,
        position: {3, 0},
        next_piece: Piece.new(:O),
        score: 0,
        lines: 0,
        level: 1,
        alive: true,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        input_queue: :queue.new()
      }

      broadcast = PlayerState.to_broadcast(state)

      # Ghost should be at ghost_position which is the lowest valid y
      # For T piece on empty board starting at {3, 0}:
      # ghost_position should be {3, 18}
      # Ghost cells should be "ghost:COLOR"
      ghost_color = "ghost:#{piece.color}"

      # Row 18: [0, 1, 0] -> cell (4, 18)
      assert Enum.at(Enum.at(broadcast.board, 18), 4) == ghost_color
      # Row 19: [1, 1, 1] -> cells (3, 19), (4, 19), (5, 19)
      assert Enum.at(Enum.at(broadcast.board, 19), 3) == ghost_color
      assert Enum.at(Enum.at(broadcast.board, 19), 4) == ghost_color
      assert Enum.at(Enum.at(broadcast.board, 19), 5) == ghost_color
    end

    test "current piece overwrites ghost when they overlap" do
      # If piece is already at the ghost position, there should be no ghost cells
      piece = Piece.new(:T)
      # Place piece at the bottom so it matches its own ghost position
      state = %PlayerState{
        player_id: "player-1",
        nickname: "Alice",
        board: Board.new(),
        current_piece: piece,
        position: {3, 18},
        next_piece: Piece.new(:O),
        score: 0,
        lines: 0,
        level: 1,
        alive: true,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        input_queue: :queue.new()
      }

      broadcast = PlayerState.to_broadcast(state)

      # The piece color should be shown (not ghost), since piece is drawn after ghost
      assert Enum.at(Enum.at(broadcast.board, 18), 4) == piece.color
      assert Enum.at(Enum.at(broadcast.board, 19), 3) == piece.color
      assert Enum.at(Enum.at(broadcast.board, 19), 4) == piece.color
      assert Enum.at(Enum.at(broadcast.board, 19), 5) == piece.color
    end

    test "does not composite piece when player is dead" do
      piece = Piece.new(:T)
      state = %PlayerState{
        player_id: "player-1",
        nickname: "Alice",
        board: Board.new(),
        current_piece: piece,
        position: {3, 5},
        next_piece: Piece.new(:O),
        score: 0,
        lines: 0,
        level: 1,
        alive: false,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        input_queue: :queue.new()
      }

      broadcast = PlayerState.to_broadcast(state)

      # Board should be all nil (empty, no pieces composited)
      for row <- broadcast.board, cell <- row do
        assert cell == nil
      end
    end

    test "does not composite when current_piece is nil" do
      state = %PlayerState{
        player_id: "player-1",
        nickname: "Alice",
        board: Board.new(),
        current_piece: nil,
        position: {3, 5},
        next_piece: Piece.new(:O),
        score: 0,
        lines: 0,
        level: 1,
        alive: true,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        input_queue: :queue.new()
      }

      broadcast = PlayerState.to_broadcast(state)

      # Board should be all nil (empty, no pieces composited)
      for row <- broadcast.board, cell <- row do
        assert cell == nil
      end

      assert broadcast.next_piece == "O"
    end

    test "next_piece is nil when next_piece field is nil" do
      state = %PlayerState{
        player_id: "player-1",
        nickname: "Alice",
        board: Board.new(),
        current_piece: nil,
        position: {3, 5},
        next_piece: nil,
        score: 0,
        lines: 0,
        level: 1,
        alive: true,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        input_queue: :queue.new()
      }

      broadcast = PlayerState.to_broadcast(state)
      assert broadcast.next_piece == nil
    end
  end

  describe "to_game_logic_map/1" do
    test "returns a plain map with all relevant fields" do
      state = PlayerState.new("player-1", "Alice")
      map = PlayerState.to_game_logic_map(state)

      assert is_map(map)
      refute is_struct(map)

      assert map.player_id == "player-1"
      assert map.board == state.board
      assert map.current_piece == state.current_piece
      assert map.position == state.position
      assert map.next_piece == state.next_piece
      assert map.score == 0
      assert map.lines == 0
      assert map.level == 1
      assert map.alive == true
      assert map.target == nil
      assert map.pending_garbage == []
      assert map.gravity_counter == 0
      assert map.gravity_threshold == 16
      assert map.pieces_placed == 0
    end
  end

  describe "from_game_logic_map/2" do
    test "updates state from game logic map" do
      state = PlayerState.new("player-1", "Alice")

      new_piece = Piece.new(:I)
      updated_map = %{
        board: Board.new(),
        current_piece: new_piece,
        position: {2, 10},
        next_piece: Piece.new(:S),
        score: 1000,
        lines: 4,
        level: 3,
        alive: true,
        target: "player-2",
        pending_garbage: [1, 2],
        gravity_counter: 5,
        gravity_threshold: 10,
        pieces_placed: 7
      }

      updated_state = PlayerState.from_game_logic_map(state, updated_map)

      # Should preserve player_id and nickname from original
      assert updated_state.player_id == "player-1"
      assert updated_state.nickname == "Alice"

      # Should update all game logic fields
      assert updated_state.current_piece == new_piece
      assert updated_state.position == {2, 10}
      assert updated_state.score == 1000
      assert updated_state.lines == 4
      assert updated_state.level == 3
      assert updated_state.alive == true
      assert updated_state.target == "player-2"
      assert updated_state.pending_garbage == [1, 2]
      assert updated_state.gravity_counter == 5
      assert updated_state.gravity_threshold == 10
      assert updated_state.pieces_placed == 7
    end

    test "preserves input_queue from original state" do
      state = PlayerState.new("player-1", "Alice")
      q = :queue.in(:left, state.input_queue)
      state = %{state | input_queue: q}

      updated_map = %{
        board: state.board,
        current_piece: state.current_piece,
        position: state.position,
        next_piece: state.next_piece,
        score: 100,
        lines: 1,
        level: 1,
        alive: true,
        target: nil,
        pending_garbage: [],
        gravity_counter: 0,
        gravity_threshold: 16,
        pieces_placed: 1
      }

      updated_state = PlayerState.from_game_logic_map(state, updated_map)
      assert updated_state.input_queue == q
    end
  end
end
