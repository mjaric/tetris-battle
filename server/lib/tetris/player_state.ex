defmodule Tetris.PlayerState do
  @moduledoc """
  Represents a single player's state in a Tetris game.

  Contains the board, current/next pieces, score, level, and other
  game-related state. Provides serialization for broadcasting to clients
  and conversion to/from plain maps for GameLogic interop.
  """

  alias Tetris.Board
  alias Tetris.Piece

  @enforce_keys [:player_id, :nickname]
  defstruct [
    :player_id,
    :nickname,
    :board,
    :current_piece,
    :position,
    :next_piece,
    :score,
    :lines,
    :level,
    :alive,
    :target,
    :pending_garbage,
    :gravity_counter,
    :gravity_threshold,
    :input_queue,
    :pieces_placed
  ]

  @type t :: %__MODULE__{
          player_id: String.t(),
          nickname: String.t(),
          board: [[nil | String.t()]],
          current_piece: Piece.t() | nil,
          position: {integer(), integer()},
          next_piece: Piece.t() | nil,
          score: non_neg_integer(),
          lines: non_neg_integer(),
          level: pos_integer(),
          alive: boolean(),
          target: String.t() | nil,
          pending_garbage: list(),
          gravity_counter: non_neg_integer(),
          gravity_threshold: pos_integer(),
          input_queue: :queue.queue(),
          pieces_placed: non_neg_integer()
        }

  @doc """
  Creates a new PlayerState for the given player_id and nickname.

  Initializes the board, spawns a random current piece centered horizontally
  at y=-1, and generates a random next piece. All counters start at zero,
  level at 1, and the player is alive.
  """
  @spec new(String.t(), String.t()) :: t()
  def new(player_id, nickname) do
    current_piece = Piece.random()
    piece_width = length(hd(current_piece.shape))
    center_x = div(Board.width() - piece_width, 2)

    %__MODULE__{
      player_id: player_id,
      nickname: nickname,
      board: Board.new(),
      current_piece: current_piece,
      position: {center_x, -1},
      next_piece: Piece.random(),
      score: 0,
      lines: 0,
      level: 1,
      alive: true,
      target: nil,
      pending_garbage: [],
      gravity_counter: 0,
      gravity_threshold: 16,
      input_queue: :queue.new(),
      pieces_placed: 0
    }
  end

  @doc """
  Returns a JSON-serializable map for broadcasting the player state to clients.

  The board includes the ghost piece and current piece composited onto
  the locked board. The ghost is drawn first, then the current piece on top,
  so the current piece overwrites the ghost where they overlap.

  Pieces are only composited if the player is alive and the current_piece is not nil.
  """
  @spec to_broadcast(t()) :: map()
  def to_broadcast(%__MODULE__{} = state) do
    %{
      nickname: state.nickname,
      board: display_board(state),
      score: state.score,
      lines: state.lines,
      level: state.level,
      alive: state.alive,
      next_piece: next_piece_type(state.next_piece),
      target: state.target,
      pending_garbage: length(state.pending_garbage)
    }
  end

  @doc """
  Converts the PlayerState to a plain map for use with GameLogic functions.

  Excludes the nickname and input_queue fields, which are not needed by
  GameLogic. Returns a regular map (not a struct).
  """
  @spec to_game_logic_map(t()) :: map()
  def to_game_logic_map(%__MODULE__{} = state) do
    %{
      player_id: state.player_id,
      board: state.board,
      current_piece: state.current_piece,
      position: state.position,
      next_piece: state.next_piece,
      score: state.score,
      lines: state.lines,
      level: state.level,
      alive: state.alive,
      target: state.target,
      pending_garbage: state.pending_garbage,
      gravity_counter: state.gravity_counter,
      gravity_threshold: state.gravity_threshold,
      pieces_placed: state.pieces_placed
    }
  end

  @doc """
  Updates a PlayerState from a GameLogic result map.

  The player_id, nickname, and input_queue are preserved from the original
  PlayerState. All other fields are updated from the game_logic_map.
  """
  @spec from_game_logic_map(t(), map()) :: t()
  def from_game_logic_map(%__MODULE__{} = original, game_logic_map) do
    %__MODULE__{
      player_id: original.player_id,
      nickname: original.nickname,
      board: game_logic_map.board,
      current_piece: game_logic_map.current_piece,
      position: game_logic_map.position,
      next_piece: game_logic_map.next_piece,
      score: game_logic_map.score,
      lines: game_logic_map.lines,
      level: game_logic_map.level,
      alive: game_logic_map.alive,
      target: game_logic_map.target,
      pending_garbage: game_logic_map.pending_garbage,
      gravity_counter: game_logic_map.gravity_counter,
      gravity_threshold: game_logic_map.gravity_threshold,
      input_queue: original.input_queue,
      pieces_placed: game_logic_map.pieces_placed
    }
  end

  # -- Private helpers --

  defp display_board(%__MODULE__{alive: true, current_piece: %Piece{} = piece} = state) do
    board = state.board

    # 1. Draw ghost piece
    {ghost_x, ghost_y} = Board.ghost_position(board, piece.shape, state.position)
    ghost_color = "ghost:#{piece.color}"
    board = composite_piece(board, piece.shape, ghost_color, {ghost_x, ghost_y})

    # 2. Draw current piece (overwrites ghost where they overlap)
    board = composite_piece(board, piece.shape, piece.color, state.position)

    board
  end

  defp display_board(%__MODULE__{} = state) do
    # Player is dead or current_piece is nil: return locked board as-is
    state.board
  end

  defp composite_piece(board, shape, color, {px, py}) do
    shape
    |> Enum.with_index()
    |> Enum.reduce(board, fn {row, sy}, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, sx}, acc2 ->
        set_cell_if_active(acc2, cell, px + sx, py + sy, color)
      end)
    end)
  end

  defp set_cell_if_active(board, 0, _bx, _by, _color), do: board

  defp set_cell_if_active(board, _cell, bx, by, color) do
    if by >= 0 and by < Board.height() and bx >= 0 and bx < Board.width() do
      List.update_at(board, by, &List.replace_at(&1, bx, color))
    else
      board
    end
  end

  defp next_piece_type(nil), do: nil
  defp next_piece_type(%Piece{type: type}), do: Atom.to_string(type)
end
