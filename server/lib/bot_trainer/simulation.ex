defmodule BotTrainer.Simulation do
  @moduledoc """
  Headless Tetris game loop for bot weight evaluation.

  Plays complete games without timing, gravity ticks, or GenServer
  overhead. Uses Board functions directly for speed.
  """

  alias Tetris.Board
  alias Tetris.BotStrategy
  alias Tetris.Piece

  @line_points %{1 => 100, 2 => 300, 3 => 500, 4 => 800}

  @type result :: %{
          lines_cleared: non_neg_integer(),
          score: non_neg_integer(),
          pieces_placed: non_neg_integer()
        }

  @type opts :: [lookahead: boolean()]

  @doc """
  Plays one full headless game using the given heuristic weights.

  Options:
    * `lookahead: true` (default) — 2-piece lookahead per move
    * `lookahead: false` — greedy single-piece evaluation (fast)
  """
  @spec play_game(map(), opts()) :: result()
  def play_game(weights, opts \\ []) do
    lookahead = Keyword.get(opts, :lookahead, true)

    state = %{
      board: Board.new(),
      current_piece: Piece.random(),
      next_piece: Piece.random(),
      score: 0,
      lines: 0,
      level: 1,
      pieces_placed: 0
    }

    game_loop(state, weights, lookahead)
  end

  @doc """
  Plays N games with the given weights, returns average lines cleared.
  """
  @spec evaluate(map(), pos_integer(), opts()) :: float()
  def evaluate(weights, num_games, opts \\ []) do
    total =
      1..num_games
      |> Enum.map(fn _ -> play_game(weights, opts) end)
      |> Enum.map(& &1.lines_cleared)
      |> Enum.sum()

    total / num_games
  end

  defp game_loop(state, weights, lookahead) do
    placements =
      BotStrategy.enumerate_placements(
        state.board,
        state.current_piece
      )

    if placements == [] do
      finish(state)
    else
      best = pick_best(placements, state.next_piece, weights, lookahead)
      apply_placement(state, best, weights, lookahead)
    end
  end

  defp pick_best(placements, _next_piece, weights, false) do
    Enum.max_by(placements, fn pl ->
      BotStrategy.score_placement(pl.metrics, weights)
    end)
  end

  defp pick_best(placements, next_piece, weights, true) do
    # Pruned lookahead: score all placements greedily, then only
    # evaluate lookahead on the top candidates. Reduces evaluations
    # from ~34*34=1156 to ~34+5*34=204 per move (~5.7x faster).
    scored =
      Enum.map(placements, fn pl ->
        {BotStrategy.score_placement(pl.metrics, weights), pl}
      end)

    top_k =
      scored
      |> Enum.sort_by(fn {s, _} -> s end, :desc)
      |> Enum.take(5)

    {_best_score, best_pl} =
      Enum.max_by(top_k, fn {greedy_score, pl} ->
        greedy_score +
          best_next_score(pl.resulting_board, next_piece, weights)
      end)

    best_pl
  end

  defp best_next_score(board, next_piece, weights) do
    case BotStrategy.enumerate_placements(board, next_piece) do
      [] ->
        -1_000_000.0

      pls ->
        pls
        |> Enum.map(fn np ->
          BotStrategy.score_placement(np.metrics, weights)
        end)
        |> Enum.max()
    end
  end

  defp apply_placement(state, placement, weights, lookahead) do
    rotated =
      apply_rotations(state.current_piece, placement.rotation_count)

    {_gx, gy} =
      Board.ghost_position(
        state.board,
        rotated.shape,
        {placement.target_x, 0}
      )

    placed =
      Board.place_piece(
        state.board,
        rotated.shape,
        rotated.color,
        {placement.target_x, gy}
      )

    {cleared_board, lines_cleared} = Board.clear_lines(placed)

    line_score =
      Map.get(@line_points, lines_cleared, 0) * state.level

    new_lines = state.lines + lines_cleared
    new_level = div(new_lines, 10) + 1

    new_piece = state.next_piece
    spawn_x = spawn_x(new_piece)

    if Board.valid_position?(cleared_board, new_piece.shape, {spawn_x, 0}) do
      new_state = %{
        state
        | board: cleared_board,
          current_piece: new_piece,
          next_piece: Piece.random(),
          score: state.score + line_score,
          lines: new_lines,
          level: new_level,
          pieces_placed: state.pieces_placed + 1
      }

      game_loop(new_state, weights, lookahead)
    else
      finish(%{
        state
        | score: state.score + line_score,
          lines: new_lines,
          pieces_placed: state.pieces_placed + 1
      })
    end
  end

  defp finish(state) do
    %{
      lines_cleared: state.lines,
      score: state.score,
      pieces_placed: state.pieces_placed
    }
  end

  defp spawn_x(piece) do
    shape_width = length(Enum.at(piece.shape, 0))
    div(Board.width() - shape_width, 2)
  end

  defp apply_rotations(piece, 0), do: piece

  defp apply_rotations(piece, n) when n > 0 do
    apply_rotations(Piece.rotate(piece), n - 1)
  end
end
