defmodule TetrisGpt.Training.GameRecorder do
  @moduledoc """
  Records bot-vs-bot battle games for training data.

  Wraps the headless battle simulation and captures every piece
  placement with full game context. Each game produces a replay
  containing per-player timelines of timestep maps.
  """

  alias Tetris.{Board, BotStrategy, Piece}

  @doc """
  Record a single 4-player bot battle.

  Returns %{players: %{0 => [timestep, ...], 1 => [...], ...}}
  """
  def record_game(opts \\ []) do
    difficulty = Keyword.get(opts, :difficulty, :hard)
    num_players = Keyword.get(opts, :num_players, 4)
    weights = BotStrategy.weights_for(difficulty)

    players = init_players(num_players)
    timelines = Map.new(0..(num_players - 1), fn id -> {id, []} end)

    {_players, timelines} =
      run_game_loop(players, timelines, weights)

    %{players: timelines}
  end

  @doc "Record multiple games. Returns a list of replays."
  def record_games(count, opts \\ []) do
    Enum.map(1..count, fn _ -> record_game(opts) end)
  end

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

  defp run_game_loop(players, timelines, weights) do
    alive_count = Enum.count(players, & &1.alive)

    if alive_count <= 1 do
      {players, timelines}
    else
      {players, timelines} =
        process_all_turns(players, timelines, weights)

      run_game_loop(players, timelines, weights)
    end
  end

  defp process_all_turns(players, timelines, weights) do
    players
    |> Enum.with_index()
    |> Enum.reduce({players, timelines}, fn {player, idx}, {ps, tl} ->
      if player.alive do
        process_player_turn(ps, tl, idx, weights)
      else
        {ps, tl}
      end
    end)
  end

  defp process_player_turn(players, timelines, idx, weights) do
    player = Enum.at(players, idx)

    # Apply pending garbage first
    {player, alive} = apply_pending_garbage(player)

    if alive do
      place_or_kill(players, timelines, idx, player, weights)
    else
      player = %{player | alive: false}
      players = List.replace_at(players, idx, player)
      {players, timelines}
    end
  end

  defp place_or_kill(players, timelines, idx, player, weights) do
    placements =
      BotStrategy.enumerate_placements(
        player.board,
        player.current_piece
      )

    if placements == [] do
      player = %{player | alive: false}
      players = List.replace_at(players, idx, player)
      {players, timelines}
    else
      do_placement(
        players,
        timelines,
        idx,
        player,
        placements,
        weights
      )
    end
  end

  defp do_placement(players, timelines, idx, player, placements, weights) do
    best = pick_best_placement(placements, weights)
    battle_ctx = build_battle_context(player, players)

    # Record timestep BEFORE applying the placement
    timestep = %{
      timestep: player.pieces_placed,
      board: player.board,
      current_piece: player.current_piece.type,
      next_piece: player.next_piece.type,
      battle_context: battle_ctx,
      placement: %{
        rotation: best.rotation_count,
        column: best.target_x
      }
    }

    timeline = Map.fetch!(timelines, idx)
    timelines = Map.put(timelines, idx, timeline ++ [timestep])

    # Apply the placement
    {board, lines_cleared} =
      apply_placement(player.board, player.current_piece, best)

    # Send garbage to target
    garbage_to_send = max(0, lines_cleared - 1)

    players =
      send_garbage(players, player.target, garbage_to_send, idx)

    # Advance to next piece
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

    # Check if next piece can spawn
    can_spawn =
      Board.valid_position?(
        board,
        player.current_piece.shape,
        {3, 0}
      )

    player = if can_spawn, do: player, else: %{player | alive: false}

    players = List.replace_at(players, idx, player)
    {players, timelines}
  end

  defp apply_pending_garbage(player) when player.pending_garbage <= 0 do
    {player, true}
  end

  defp apply_pending_garbage(player) do
    rows =
      Enum.map(1..player.pending_garbage, fn _ ->
        Board.generate_garbage_row()
      end)

    {board, overflow} = Board.add_garbage(player.board, rows)
    # overflow=true means cells pushed off top => player dies
    {%{player | board: board, pending_garbage: 0}, not overflow}
  end

  defp pick_best_placement(placements, weights) do
    Enum.max_by(placements, fn pl ->
      BotStrategy.score_placement(pl.metrics, weights)
    end)
  end

  defp build_battle_context(player, all_players) do
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
      pending_garbage_count: player.pending_garbage,
      own_max_height: max_height_from_board(player.board),
      opponent_max_height: opp_max,
      combo_count: player.combo_count,
      lines: player.lines,
      score_diff: player.score - opp_leading_score,
      opponent_count: length(opponents),
      alive: player.alive
    }
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

  defp send_garbage(players, _target_id, 0, _sender_id), do: players

  defp send_garbage(players, target_id, amount, sender_id) do
    List.update_at(players, target_id, fn target ->
      if target.alive and target.id != sender_id do
        %{target | pending_garbage: target.pending_garbage + amount}
      else
        target
      end
    end)
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
  defp score_lines(4, level), do: 800 * level
end
