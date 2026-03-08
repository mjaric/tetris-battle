defmodule TetrisGpt.Training.BenchmarkSimulation do
  @moduledoc """
  Runs battle simulations between a Strategy-based player and
  heuristic bot opponents. Used by the benchmark mix task to
  measure GPT model performance against baseline bots.
  """

  alias Tetris.{Board, BotStrategy, Piece}

  @doc """
  Run a single benchmark game.

  Player 0 uses the given strategy module/state. Players 1-3 use
  heuristic bots at the specified difficulty.

  Returns a result map with winner, per-player stats, and the
  updated strategy state (for reuse across games).
  """
  def run_game(strategy_mod, strategy_state, opts \\ []) do
    difficulty = Keyword.get(opts, :difficulty, :hard)
    num_opponents = Keyword.get(opts, :num_opponents, 3)
    num_players = 1 + num_opponents
    weights = BotStrategy.weights_for(difficulty)

    players = init_players(num_players)

    strategies =
      Map.new(0..(num_players - 1), fn
        0 -> {0, {:gpt, strategy_mod, strategy_state}}
        id -> {id, {:heuristic, weights}}
      end)

    {players, strategies} =
      run_game_loop(players, strategies)

    # Determine winner (last player alive, or player with most lines)
    winner = find_winner(players)

    stats =
      Map.new(players, fn p ->
        {p.id,
         %{
           alive: p.alive,
           lines: p.lines,
           score: p.score,
           pieces_placed: p.pieces_placed,
           is_gpt: p.id == 0
         }}
      end)

    # Extract updated strategy state
    {_, _, updated_strategy_state} = Map.fetch!(strategies, 0)

    %{
      winner: winner,
      gpt_won: winner == 0,
      stats: stats,
      strategy_state: updated_strategy_state
    }
  end

  @doc """
  Run multiple benchmark games and aggregate results.

  Returns a summary map with win rate, average stats, and
  per-game results.
  """
  def run_benchmark(strategy_mod, strategy_state, opts \\ []) do
    num_games = Keyword.get(opts, :num_games, 20)
    difficulty = Keyword.get(opts, :difficulty, :hard)

    {results, _final_state} =
      Enum.map_reduce(1..num_games, strategy_state, fn game_num, state ->
        result =
          run_game(strategy_mod, state, difficulty: difficulty)

        {Map.put(result, :game_num, game_num), result.strategy_state}
      end)

    gpt_wins = Enum.count(results, & &1.gpt_won)
    total = length(results)

    avg_lines =
      results
      |> Enum.map(fn r -> r.stats[0].lines end)
      |> average()

    avg_pieces =
      results
      |> Enum.map(fn r -> r.stats[0].pieces_placed end)
      |> average()

    %{
      games: total,
      gpt_wins: gpt_wins,
      win_rate: gpt_wins / max(total, 1),
      avg_gpt_lines: avg_lines,
      avg_gpt_pieces: avg_pieces,
      results: results
    }
  end

  # -- Player initialization --

  defp init_players(num_players) do
    Enum.map(0..(num_players - 1), fn id ->
      %{
        id: id,
        board: Board.new(),
        current_piece: Piece.random(),
        next_piece: Piece.random(),
        score: 0,
        lines: 0,
        level: 1,
        pieces_placed: 0,
        pending_garbage: 0,
        target: rem(id + 1, num_players),
        alive: true,
        combo_count: 0
      }
    end)
  end

  # -- Game loop --

  defp run_game_loop(players, strategies) do
    alive_count = Enum.count(players, & &1.alive)

    if alive_count <= 1 do
      {players, strategies}
    else
      {players, strategies} =
        process_all_turns(players, strategies)

      run_game_loop(players, strategies)
    end
  end

  defp process_all_turns(players, strategies) do
    players
    |> Enum.with_index()
    |> Enum.reduce({players, strategies}, fn {player, idx}, {ps, strats} ->
      if player.alive do
        process_turn(ps, strats, idx)
      else
        {ps, strats}
      end
    end)
  end

  defp process_turn(players, strategies, idx) do
    player = Enum.at(players, idx)

    {player, alive} = apply_pending_garbage(player)

    if alive do
      place_piece(players, strategies, idx, player)
    else
      player = %{player | alive: false}
      players = List.replace_at(players, idx, player)
      {players, strategies}
    end
  end

  defp place_piece(players, strategies, idx, player) do
    placements =
      BotStrategy.enumerate_placements(
        player.board,
        player.current_piece
      )

    if placements == [] do
      player = %{player | alive: false}
      players = List.replace_at(players, idx, player)
      {players, strategies}
    else
      do_place(players, strategies, idx, player, placements)
    end
  end

  defp do_place(players, strategies, idx, player, placements) do
    strategy = Map.fetch!(strategies, idx)

    {placement, strategies} =
      choose_placement(
        strategy,
        strategies,
        idx,
        player,
        players,
        placements
      )

    {board, lines_cleared} =
      apply_placement(player.board, player.current_piece, placement)

    garbage_to_send = max(0, lines_cleared - 1)

    players =
      send_garbage(players, player.target, garbage_to_send, idx)

    new_lines = player.lines + lines_cleared

    player = %{
      player
      | board: board,
        current_piece: player.next_piece,
        next_piece: Piece.random(),
        lines: new_lines,
        score: player.score + score_lines(lines_cleared, player.level),
        pieces_placed: player.pieces_placed + 1,
        level: div(new_lines, 10) + 1,
        combo_count:
          if(lines_cleared > 0,
            do: player.combo_count + 1,
            else: 0
          )
    }

    can_spawn =
      Board.valid_position?(
        board,
        player.current_piece.shape,
        {3, 0}
      )

    player = if can_spawn, do: player, else: %{player | alive: false}

    players = List.replace_at(players, idx, player)
    {players, strategies}
  end

  # -- Strategy dispatch --

  defp choose_placement(
         {:gpt, mod, state},
         strategies,
         idx,
         player,
         all_players,
         _placements
       ) do
    context = build_strategy_context(player, all_players)
    {placement, new_state} = mod.predict(state, context)

    strategies =
      Map.put(strategies, idx, {:gpt, mod, new_state})

    {%{rotation_count: placement.rotation, target_x: placement.column}, strategies}
  end

  defp choose_placement(
         {:heuristic, weights},
         strategies,
         _idx,
         _player,
         _all_players,
         placements
       ) do
    best =
      Enum.max_by(placements, fn pl ->
        BotStrategy.score_placement(pl.metrics, weights)
      end)

    {best, strategies}
  end

  defp build_strategy_context(player, all_players) do
    opponents =
      Enum.filter(all_players, fn p ->
        p.id != player.id and p.alive
      end)

    opp_max =
      opponents
      |> Enum.map(fn p -> max_height_from_board(p.board) end)
      |> Enum.max(fn -> 0 end)

    opp_leading_score =
      opponents
      |> Enum.map(& &1.score)
      |> Enum.max(fn -> 0 end)

    %{
      board: player.board,
      current_piece: player.current_piece.type,
      next_piece: player.next_piece.type,
      battle_context: %{
        pending_garbage_count: player.pending_garbage,
        own_max_height: max_height_from_board(player.board),
        opponent_max_height: opp_max,
        combo_count: player.combo_count,
        lines: player.lines,
        score_diff: player.score - opp_leading_score,
        opponent_count: length(opponents),
        alive: player.alive
      }
    }
  end

  # -- Shared helpers (same as GameRecorder) --

  defp apply_pending_garbage(player)
       when player.pending_garbage <= 0 do
    {player, true}
  end

  defp apply_pending_garbage(player) do
    rows =
      Enum.map(1..player.pending_garbage, fn _ ->
        Board.generate_garbage_row()
      end)

    {board, overflow} = Board.add_garbage(player.board, rows)
    {%{player | board: board, pending_garbage: 0}, not overflow}
  end

  defp apply_placement(board, piece, placement) do
    rotated_piece =
      Enum.reduce(1..placement.rotation_count//1, piece, fn _, p ->
        Piece.rotate(p)
      end)

    {_gx, gy} =
      Board.ghost_position(
        board,
        rotated_piece.shape,
        {placement.target_x, 0}
      )

    board =
      Board.place_piece(
        board,
        rotated_piece.shape,
        rotated_piece.color,
        {placement.target_x, gy}
      )

    Board.clear_lines(board)
  end

  defp send_garbage(players, _target_id, 0, _sender_id),
    do: players

  defp send_garbage(players, target_id, amount, sender_id) do
    List.update_at(players, target_id, fn target ->
      if target.alive and target.id != sender_id do
        %{target | pending_garbage: target.pending_garbage + amount}
      else
        target
      end
    end)
  end

  defp find_winner(players) do
    alive = Enum.filter(players, & &1.alive)

    case alive do
      [winner] -> winner.id
      [] -> players |> Enum.max_by(& &1.lines) |> Map.get(:id)
      many -> many |> Enum.max_by(& &1.lines) |> Map.get(:id)
    end
  end

  defp max_height_from_board(board) do
    board
    |> Enum.with_index()
    |> Enum.find_value(0, fn {row, idx} ->
      if Enum.any?(row, &(&1 != nil)), do: 20 - idx
    end)
  end

  defp score_lines(0, _level), do: 0
  defp score_lines(1, level), do: 100 * level
  defp score_lines(2, level), do: 300 * level
  defp score_lines(3, level), do: 500 * level
  defp score_lines(_, level), do: 800 * level

  defp average([]), do: 0.0

  defp average(list) do
    Enum.sum(list) / length(list)
  end
end
