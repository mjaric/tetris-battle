defmodule TetrisGpt.Strategies.Heuristic do
  @moduledoc """
  Wraps the existing BotStrategy behind the Strategy behaviour.
  Used as a baseline for benchmarking TetrisGpt.
  """

  @behaviour TetrisGpt.Strategy

  alias Tetris.{BotStrategy, Piece}

  @impl true
  def name, do: "heuristic"

  @impl true
  def init(opts) do
    difficulty = Keyword.get(opts, :difficulty, :hard)
    %{difficulty: difficulty}
  end

  @impl true
  def predict(state, context) do
    piece = Piece.new(context.current_piece)
    next = Piece.new(context.next_piece)
    spawn_x = 3

    {rot, col, _actions} =
      BotStrategy.best_placement(
        context.board,
        piece,
        {spawn_x, 0},
        next,
        state.difficulty
      )

    placement = %{rotation: rot, column: col}
    {placement, state}
  end
end
