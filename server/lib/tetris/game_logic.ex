defmodule Tetris.GameLogic do
  @moduledoc """
  Core game mechanics for Tetris: move, rotate, lock, spawn, gravity, and scoring.

  All functions operate on a state map with the following keys:
  - board, current_piece, position, next_piece, score, lines, level,
    alive, pending_garbage, gravity_counter, gravity_threshold
  """

  alias Tetris.Board
  alias Tetris.Piece
  alias Tetris.WallKicks

  @line_points %{1 => 100, 2 => 300, 3 => 500, 4 => 800}

  @doc """
  Move the current piece one cell to the left.
  Returns `{:ok, new_state}` or `:invalid`.
  """
  @spec move_left(map()) :: {:ok, map()} | :invalid
  def move_left(%{board: board, current_piece: piece, position: {px, py}} = state) do
    new_pos = {px - 1, py}

    if Board.valid_position?(board, piece.shape, new_pos) do
      {:ok, %{state | position: new_pos}}
    else
      :invalid
    end
  end

  @doc """
  Move the current piece one cell to the right.
  Returns `{:ok, new_state}` or `:invalid`.
  """
  @spec move_right(map()) :: {:ok, map()} | :invalid
  def move_right(%{board: board, current_piece: piece, position: {px, py}} = state) do
    new_pos = {px + 1, py}

    if Board.valid_position?(board, piece.shape, new_pos) do
      {:ok, %{state | position: new_pos}}
    else
      :invalid
    end
  end

  @doc """
  Move the current piece one cell down.
  Returns `{:ok, :moved, new_state}` if moved, or `{:ok, :locked, new_state}` if the piece
  was locked in place (calls lock_and_spawn internally).
  """
  @spec move_down(map()) :: {:ok, :moved, map()} | {:ok, :locked, map()}
  def move_down(%{board: board, current_piece: piece, position: {px, py}} = state) do
    new_pos = {px, py + 1}

    if Board.valid_position?(board, piece.shape, new_pos) do
      {:ok, :moved, %{state | position: new_pos}}
    else
      lock_and_spawn(state)
    end
  end

  @doc """
  Rotate the current piece clockwise with SRS wall kicks.
  Returns `{:ok, new_state}` or `:invalid` if no valid rotation exists.
  """
  @spec rotate(map()) :: {:ok, map()} | :invalid
  def rotate(%{board: board, current_piece: piece, position: {px, py}} = state) do
    rotated_piece = Piece.rotate(piece)
    old_rotation = piece.rotation
    new_rotation = rotated_piece.rotation
    kicks = WallKicks.get(piece.type, {old_rotation, new_rotation})

    result =
      Enum.find_value(kicks, fn {dx, dy} ->
        # SRS convention: negate dy
        new_pos = {px + dx, py - dy}

        if Board.valid_position?(board, rotated_piece.shape, new_pos) do
          {rotated_piece, new_pos}
        end
      end)

    case result do
      {new_piece, new_pos} ->
        {:ok, %{state | current_piece: new_piece, position: new_pos}}

      nil ->
        :invalid
    end
  end

  @doc """
  Hard drop: instantly drop the piece to its ghost position, add score (distance * 2),
  and lock the piece.
  Returns `{:ok, new_state}`.
  """
  @spec hard_drop(map()) :: {:ok, map()}
  def hard_drop(%{board: board, current_piece: piece, position: {px, py}} = state) do
    {_gx, gy} = Board.ghost_position(board, piece.shape, {px, py})
    distance = gy - py
    drop_score = distance * 2

    state = %{state | position: {px, gy}, score: state.score + drop_score}

    {:ok, :locked, locked_state} = lock_and_spawn(state)
    {:ok, locked_state}
  end

  @doc """
  Apply gravity: increment the gravity counter. When it reaches the threshold,
  call move_down and reset the counter.
  Returns `{:ok, :locked, state}`, `{:ok, :moved, state}`, or `{:ok, :waiting, state}`.
  """
  @spec apply_gravity(map()) :: {:ok, :locked | :moved | :waiting, map()}
  def apply_gravity(%{gravity_counter: counter, gravity_threshold: threshold} = state) do
    new_counter = counter + 1

    if new_counter >= threshold do
      case move_down(%{state | gravity_counter: 0}) do
        {:ok, :moved, new_state} -> {:ok, :moved, new_state}
        {:ok, :locked, new_state} -> {:ok, :locked, new_state}
      end
    else
      {:ok, :waiting, %{state | gravity_counter: new_counter}}
    end
  end

  @doc """
  Spawn the next piece at the top center of the board.
  Returns `{:ok, state}` or `{:game_over, state}` if the spawn position is blocked.
  """
  @spec spawn_piece(map()) :: {:ok, map()} | {:game_over, map()}
  def spawn_piece(%{board: board, next_piece: next_piece} = state) do
    shape_width = length(Enum.at(next_piece.shape, 0))
    spawn_x = div(Board.width() - shape_width, 2)
    spawn_y = 0
    spawn_pos = {spawn_x, spawn_y}

    if Board.valid_position?(board, next_piece.shape, spawn_pos) do
      new_next = Piece.random()

      {:ok,
       %{
         state
         | current_piece: next_piece,
           position: spawn_pos,
           next_piece: new_next,
           gravity_counter: 0
       }}
    else
      {:game_over, %{state | alive: false}}
    end
  end

  @doc """
  Apply pending garbage rows to the board.
  Returns `{:ok, state}` or `{:game_over, state}` if garbage causes overflow.
  """
  @spec apply_pending_garbage(map()) :: {:ok, map()} | {:game_over, map()}
  def apply_pending_garbage(%{pending_garbage: []} = state) do
    {:ok, state}
  end

  def apply_pending_garbage(%{board: board, pending_garbage: garbage_rows} = state) do
    {new_board, overflow} = Board.add_garbage(board, garbage_rows)
    state = %{state | board: new_board, pending_garbage: []}

    if overflow do
      {:game_over, %{state | alive: false}}
    else
      {:ok, state}
    end
  end

  @doc """
  Calculate the gravity threshold for a given level.
  Returns `max(2, 16 - (level - 1))` frames between drops.
  """
  @spec gravity_threshold(pos_integer()) :: pos_integer()
  def gravity_threshold(level) do
    max(2, 16 - (level - 1))
  end

  # -- Internal: lock_and_spawn --

  defp lock_and_spawn(%{board: board, current_piece: piece, position: pos} = state) do
    # 1. Place piece on board
    new_board = Board.place_piece(board, piece.shape, piece.color, pos)

    # 2. Clear lines, update score
    {cleared_board, lines_cleared} = Board.clear_lines(new_board)

    line_score = Map.get(@line_points, lines_cleared, 0) * state.level
    new_score = state.score + line_score

    # 3. Update lines count, calculate new level
    new_lines = state.lines + lines_cleared
    new_level = div(new_lines, 10) + 1
    new_threshold = gravity_threshold(new_level)

    state = %{
      state
      | board: cleared_board,
        score: new_score,
        lines: new_lines,
        level: new_level,
        gravity_threshold: new_threshold
    }

    # 4. Spawn next piece (garbage is applied in the tick loop)
    case spawn_piece(state) do
      {:ok, spawned_state} ->
        {:ok, :locked, Map.put(spawned_state, :lines_cleared_this_lock, lines_cleared)}

      {:game_over, dead_state} ->
        {:ok, :locked, Map.put(dead_state, :lines_cleared_this_lock, lines_cleared)}
    end
  end
end
