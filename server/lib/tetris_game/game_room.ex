defmodule TetrisGame.GameRoom do
  @moduledoc """
  GenServer that manages a multiplayer Tetris game room.

  Handles player join/leave, game start, input processing, gravity,
  garbage distribution, elimination tracking, and state broadcasting
  via a 50ms tick loop (20 FPS).
  """

  use GenServer
  require Logger

  alias Tetris.Board
  alias Tetris.GameLogic
  alias Tetris.PlayerState
  alias TetrisGame.BotNames
  alias TetrisGame.BotSupervisor
  alias TetrisGame.Lobby

  @tick_interval 50

  defstruct [
    :room_id,
    :host,
    :name,
    :max_players,
    :status,
    :players,
    :player_order,
    :eliminated_order,
    :tick,
    :tick_timer,
    :bot_ids,
    :bot_pids
  ]

  @type t :: %__MODULE__{
          room_id: String.t(),
          host: String.t(),
          name: String.t(),
          max_players: pos_integer(),
          status: :waiting | :playing | :finished,
          players: %{String.t() => PlayerState.t()},
          player_order: [String.t()],
          eliminated_order: [String.t()],
          tick: non_neg_integer(),
          tick_timer: reference() | nil,
          bot_ids: MapSet.t(),
          bot_pids: %{String.t() => pid()}
        }

  # -- Client API --

  @doc """
  Returns a via tuple for registry lookup by room_id.
  """
  def via(room_id) do
    {:via, Registry, {TetrisGame.RoomRegistry, room_id}}
  end

  @doc """
  Starts the GameRoom GenServer.

  Options:
    - `:room_id` - unique room identifier (required)
    - `:host` - player_id of the host (required)
    - `:name` - room display name (required)
    - `:max_players` - maximum number of players (required)
  """
  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  @doc """
  Joins a player to the room.

  Returns `:ok` on success, or `{:error, reason}` where reason is
  `:room_full`, `:already_joined`, or `:game_in_progress`.
  """
  def join(room, player_id, nickname) do
    GenServer.call(room, {:join, player_id, nickname})
  end

  @doc """
  Removes a player from the room.

  If the host leaves, the oldest remaining player becomes host.
  If the room becomes empty, the GenServer stops.
  """
  def leave(room, player_id) do
    GenServer.call(room, {:leave, player_id})
  end

  @doc """
  Starts the game. Only the host can start, and at least 2 players are required.

  Sets default targets (each player targets the next in join order, wrapping around).
  Starts the tick timer.
  """
  def start_game(room, requester_id) do
    GenServer.call(room, {:start_game, requester_id})
  end

  @doc """
  Queues an input action for a player. This is a cast (fire and forget).

  Valid actions: "move_left", "move_right", "move_down", "rotate", "hard_drop"
  """
  def input(room, player_id, action) do
    GenServer.cast(room, {:input, player_id, action})
    :ok
  end

  @doc """
  Changes who a player sends garbage to.

  Returns `:ok` on success, or `{:error, :invalid_target}`.
  """
  def set_target(room, player_id, target_id) do
    GenServer.call(room, {:set_target, player_id, target_id})
  end

  @doc """
  Adds a bot player to the room. Only allowed in waiting state.

  Returns `{:ok, bot_id}` or `{:error, reason}`.
  """
  def add_bot(room, difficulty) do
    GenServer.call(room, {:add_bot, difficulty})
  end

  @doc """
  Removes a bot player from the room. Only allowed in waiting state.
  """
  def remove_bot(room, bot_id) do
    GenServer.call(room, {:remove_bot, bot_id})
  end

  @doc """
  Returns the full room state (for debugging/testing).
  """
  def get_state(room) do
    GenServer.call(room, :get_state)
  end

  # -- Server Callbacks --

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    host = Keyword.fetch!(opts, :host)
    name = Keyword.fetch!(opts, :name)
    max_players = Keyword.fetch!(opts, :max_players)

    state = %__MODULE__{
      room_id: room_id,
      host: host,
      name: name,
      max_players: max_players,
      status: :waiting,
      players: %{},
      player_order: [],
      eliminated_order: [],
      tick: 0,
      tick_timer: nil,
      bot_ids: MapSet.new(),
      bot_pids: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id, nickname}, _from, state) do
    cond do
      state.status != :waiting ->
        {:reply, {:error, :game_in_progress}, state}

      Map.has_key?(state.players, player_id) ->
        {:reply, :ok, state}

      map_size(state.players) >= state.max_players ->
        {:reply, {:error, :room_full}, state}

      true ->
        player = PlayerState.new(player_id, nickname)

        new_state = %{
          state
          | players: Map.put(state.players, player_id, player),
            player_order: state.player_order ++ [player_id]
        }

        Lobby.update_room(
          state.room_id,
          %{player_count: map_size(new_state.players)}
        )

        broadcast_state(new_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    is_player = Map.has_key?(state.players, player_id)
    is_host = state.host == player_id

    if is_player or is_host do
      do_leave(state, player_id, is_player, is_host)
    else
      {:reply, :ok, state}
    end
  end

  defp do_leave(state, player_id, is_player, is_host) do
    new_players = if is_player, do: Map.delete(state.players, player_id), else: state.players
    new_order = if is_player, do: List.delete(state.player_order, player_id), else: state.player_order

    remaining_humans = Enum.reject(new_order, &MapSet.member?(state.bot_ids, &1))
    room_empty = map_size(new_players) == 0 and is_host
    all_bots = remaining_humans == [] and map_size(new_players) > 0

    if room_empty or all_bots do
      stop_all_bots(state)
      Lobby.update_room(state.room_id, %{player_count: 0})
      {:stop, :normal, :ok, state}
    else
      new_host = if is_host and remaining_humans != [], do: hd(remaining_humans), else: state.host
      new_state = %{state | players: new_players, player_order: new_order, host: new_host}
      Lobby.update_room(state.room_id, %{player_count: map_size(new_players)})
      broadcast_state(new_state)
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:start_game, requester_id}, _from, state) do
    cond do
      state.status != :waiting ->
        {:reply, {:error, :already_started}, state}

      requester_id != state.host ->
        {:reply, {:error, :not_host}, state}

      map_size(state.players) < 2 ->
        {:reply, {:error, :not_enough_players}, state}

      true ->
        players_with_targets =
          set_default_targets(state.players, state.player_order)

        target_summary =
          Map.new(players_with_targets, fn {_pid, p} ->
            {p.nickname, players_with_targets[p.target].nickname}
          end)

        Logger.debug(
          "[Game] started room=#{state.room_id} " <>
            "targets=#{inspect(target_summary)}"
        )

        timer_ref = schedule_tick()

        new_state = %{
          state
          | status: :playing,
            players: players_with_targets,
            tick_timer: timer_ref
        }

        Enum.each(state.bot_pids, fn {_, pid} ->
          send(pid, :game_started)
        end)

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:set_target, player_id, target_id}, _from, state) do
    cond do
      not Map.has_key?(state.players, target_id) ->
        {:reply, {:error, :invalid_target}, state}

      player_id == target_id ->
        {:reply, {:error, :invalid_target}, state}

      true ->
        player = state.players[player_id]
        updated_player = %{player | target: target_id}
        new_players = Map.put(state.players, player_id, updated_player)
        {:reply, :ok, %{state | players: new_players}}
    end
  end

  def handle_call({:add_bot, difficulty}, _from, state) do
    cond do
      state.status != :waiting ->
        {:reply, {:error, :game_in_progress}, state}

      map_size(state.players) >= state.max_players ->
        {:reply, {:error, :room_full}, state}

      true ->
        bot_id = "bot-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
        existing_names = Enum.map(state.players, fn {_, p} -> p.nickname end)
        nickname = BotNames.pick(existing_names)

        player = PlayerState.new(bot_id, nickname)

        bot_opts = [
          bot_id: bot_id,
          nickname: nickname,
          room_id: state.room_id,
          difficulty: difficulty,
          room_pid: self()
        ]

        case BotSupervisor.start_bot(bot_opts) do
          {:ok, bot_pid} ->
            Process.monitor(bot_pid)

            new_state = %{
              state
              | players: Map.put(state.players, bot_id, player),
                player_order: state.player_order ++ [bot_id],
                bot_ids: MapSet.put(state.bot_ids, bot_id),
                bot_pids: Map.put(state.bot_pids, bot_id, bot_pid)
            }

            Lobby.update_room(
              state.room_id,
              %{player_count: map_size(new_state.players)}
            )

            broadcast_state(new_state)
            {:reply, {:ok, bot_id}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:remove_bot, bot_id}, _from, state) do
    cond do
      state.status != :waiting ->
        {:reply, {:error, :game_in_progress}, state}

      not MapSet.member?(state.bot_ids, bot_id) ->
        {:reply, {:error, :not_a_bot}, state}

      true ->
        bot_pid = state.bot_pids[bot_id]

        if bot_pid do
          BotSupervisor.stop_bot(bot_pid)
        end

        new_state = %{
          state
          | players: Map.delete(state.players, bot_id),
            player_order: List.delete(state.player_order, bot_id),
            bot_ids: MapSet.delete(state.bot_ids, bot_id),
            bot_pids: Map.delete(state.bot_pids, bot_id)
        }

        Lobby.update_room(
          state.room_id,
          %{player_count: map_size(new_state.players)}
        )

        broadcast_state(new_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:input, player_id, action}, state) do
    case Map.fetch(state.players, player_id) do
      {:ok, player} ->
        if player.alive do
          updated_queue = :queue.in(action, player.input_queue)
          updated_player = %{player | input_queue: updated_queue}
          new_players = Map.put(state.players, player_id, updated_player)
          {:noreply, %{state | players: new_players}}
        else
          {:noreply, state}
        end

      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    state = process_tick(state)

    if state.status == :playing do
      timer_ref = schedule_tick()
      {:noreply, %{state | tick_timer: timer_ref}}
    else
      {:noreply, %{state | tick_timer: nil}}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Enum.find(state.bot_pids, fn {_, p} -> p == pid end) do
      {bot_id, _} ->
        Logger.debug("[Game] bot #{bot_id} process down, cleaning up")

        new_state =
          if state.status == :waiting do
            %{
              state
              | players: Map.delete(state.players, bot_id),
                player_order: List.delete(state.player_order, bot_id),
                bot_ids: MapSet.delete(state.bot_ids, bot_id),
                bot_pids: Map.delete(state.bot_pids, bot_id)
            }
          else
            %{
              state
              | bot_pids: Map.delete(state.bot_pids, bot_id)
            }
          end

        Lobby.update_room(
          state.room_id,
          %{player_count: map_size(new_state.players)}
        )

        broadcast_state(new_state)
        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  # -- Tick processing --

  defp process_tick(state) do
    # 1. Increment tick counter
    state = %{state | tick: state.tick + 1}

    # 2. For each alive player: drain input_queue, apply each action via GameLogic
    {players_after_input, garbage_events_from_input} =
      process_all_inputs(state.players, state.player_order)

    # 3. For each alive player: apply_gravity via GameLogic
    {players_after_gravity, garbage_events_from_gravity} =
      process_all_gravity(players_after_input, state.player_order)

    # 4. Combine all garbage events
    all_garbage_events = garbage_events_from_input ++ garbage_events_from_gravity

    if all_garbage_events != [] do
      Logger.debug("[Garbage] events=#{inspect(all_garbage_events)}")
    end

    # 5. Distribute garbage
    players_after_garbage = distribute_garbage(players_after_gravity, all_garbage_events)

    if all_garbage_events != [] do
      pending_summary =
        Map.new(players_after_garbage, fn {pid, p} ->
          {pid, length(p.pending_garbage)}
        end)

      Logger.debug("[Garbage] pending after distribute: #{inspect(pending_summary)}")
    end

    # 5b. Apply pending garbage immediately
    players_after_apply = apply_all_pending_garbage(players_after_garbage, state.player_order)

    # 6. Check eliminations
    {players_final, new_eliminations} =
      check_eliminations(players_after_apply, state.players, state.player_order)

    eliminated_order = state.eliminated_order ++ new_eliminations

    # 7. Check victory
    alive_count =
      players_final
      |> Map.values()
      |> Enum.count(& &1.alive)

    new_status =
      if alive_count <= 1 do
        :finished
      else
        state.status
      end

    state = %{
      state
      | players: players_final,
        eliminated_order: eliminated_order,
        status: new_status
    }

    # 8. Broadcast state
    broadcast_state(state)

    state
  end

  # -- Input processing --

  defp process_all_inputs(players, player_order) do
    Enum.reduce(player_order, {players, []}, fn player_id, {acc_players, acc_garbage} ->
      player = acc_players[player_id]

      if player.alive do
        {updated_player, garbage_events} = drain_input_queue(player)
        {Map.put(acc_players, player_id, updated_player), acc_garbage ++ garbage_events}
      else
        {acc_players, acc_garbage}
      end
    end)
  end

  defp drain_input_queue(player) do
    game_map = PlayerState.to_game_logic_map(player)
    {updated_map, garbage_events} = drain_queue(player.input_queue, game_map, player.target, [])
    updated_player = PlayerState.from_game_logic_map(player, updated_map)
    # Clear the queue since we drained it
    updated_player = %{updated_player | input_queue: :queue.new()}
    {updated_player, garbage_events}
  end

  defp drain_queue(queue, game_map, target, garbage_events) do
    case :queue.out(queue) do
      {:empty, _} ->
        {game_map, garbage_events}

      {{:value, action}, rest} ->
        {new_map, new_garbage} = apply_action(action, game_map, target)
        drain_queue(rest, new_map, target, garbage_events ++ new_garbage)
    end
  end

  defp apply_action("move_left", game_map, _target) do
    case GameLogic.move_left(game_map) do
      {:ok, new_map} -> {new_map, []}
      :invalid -> {game_map, []}
    end
  end

  defp apply_action("move_right", game_map, _target) do
    case GameLogic.move_right(game_map) do
      {:ok, new_map} -> {new_map, []}
      :invalid -> {game_map, []}
    end
  end

  defp apply_action("move_down", game_map, target) do
    case GameLogic.move_down(game_map) do
      {:ok, :moved, new_map} ->
        {new_map, []}

      {:ok, :locked, new_map} ->
        garbage = collect_garbage_events(new_map, target)
        {Map.delete(new_map, :lines_cleared_this_lock), garbage}
    end
  end

  defp apply_action("rotate", game_map, _target) do
    case GameLogic.rotate(game_map) do
      {:ok, new_map} -> {new_map, []}
      :invalid -> {game_map, []}
    end
  end

  defp apply_action("hard_drop", game_map, target) do
    {:ok, new_map} = GameLogic.hard_drop(game_map)
    garbage = collect_garbage_events(new_map, target)
    {Map.delete(new_map, :lines_cleared_this_lock), garbage}
  end

  defp apply_action(_unknown, game_map, _target) do
    {game_map, []}
  end

  # -- Gravity processing --

  defp process_all_gravity(players, player_order) do
    Enum.reduce(player_order, {players, []}, fn player_id, {acc_players, acc_garbage} ->
      player = acc_players[player_id]

      if player.alive do
        apply_gravity_for_player(acc_players, acc_garbage, player_id, player)
      else
        {acc_players, acc_garbage}
      end
    end)
  end

  defp apply_gravity_for_player(acc_players, acc_garbage, player_id, player) do
    game_map = PlayerState.to_game_logic_map(player)

    case GameLogic.apply_gravity(game_map) do
      {:ok, :locked, new_map} ->
        garbage = collect_garbage_events(new_map, player.target)
        clean_map = Map.delete(new_map, :lines_cleared_this_lock)
        updated_player = PlayerState.from_game_logic_map(player, clean_map)
        {Map.put(acc_players, player_id, updated_player), acc_garbage ++ garbage}

      {:ok, _status, new_map} ->
        updated_player = PlayerState.from_game_logic_map(player, new_map)
        {Map.put(acc_players, player_id, updated_player), acc_garbage}
    end
  end

  # -- Garbage distribution --

  defp collect_garbage_events(game_map, target) do
    lines_cleared = Map.get(game_map, :lines_cleared_this_lock, 0)

    if lines_cleared > 0 do
      Logger.debug(
        "[Garbage] lock cleared #{lines_cleared} line(s), " <>
          "target=#{inspect(target)}, " <>
          "sends_garbage=#{lines_cleared >= 2}"
      )
    end

    if lines_cleared >= 2 and target != nil do
      garbage_count = lines_cleared - 1
      [{target, garbage_count}]
    else
      []
    end
  end

  defp distribute_garbage(players, garbage_events) do
    Enum.reduce(garbage_events, players, fn {target_id, count}, acc_players ->
      case Map.fetch(acc_players, target_id) do
        {:ok, target_player} -> add_garbage_to_player(acc_players, target_id, target_player, count)
        :error -> acc_players
      end
    end)
  end

  defp add_garbage_to_player(players, target_id, target_player, count) do
    if target_player.alive do
      garbage_rows = for _i <- 1..count, do: Board.generate_garbage_row()
      updated_target = %{target_player | pending_garbage: target_player.pending_garbage ++ garbage_rows}
      Map.put(players, target_id, updated_target)
    else
      players
    end
  end

  # -- Immediate garbage application --

  defp apply_all_pending_garbage(players, player_order) do
    Enum.reduce(player_order, players, fn player_id, acc ->
      player = acc[player_id]

      if player.alive and player.pending_garbage != [] do
        game_map = PlayerState.to_game_logic_map(player)

        updated_map =
          case GameLogic.apply_pending_garbage(game_map) do
            {:ok, s} -> s
            {:game_over, s} -> s
          end

        updated_player = PlayerState.from_game_logic_map(player, updated_map)
        Map.put(acc, player_id, updated_player)
      else
        acc
      end
    end)
  end

  # -- Elimination checking --

  defp check_eliminations(current_players, previous_players, player_order) do
    new_eliminations =
      Enum.filter(player_order, fn player_id ->
        prev = previous_players[player_id]
        curr = current_players[player_id]
        prev != nil and curr != nil and prev.alive and not curr.alive
      end)

    {current_players, new_eliminations}
  end

  # -- Broadcasting --

  @doc """
  Builds the broadcast payload map from a GameRoom state struct.
  """
  def build_broadcast_payload(state) do
    bot_ids = state.bot_ids || MapSet.new()

    %{
      tick: state.tick,
      status: state.status,
      host: state.host,
      players:
        Map.new(state.players, fn {player_id, player} ->
          broadcast = PlayerState.to_broadcast(player)
          broadcast = Map.put(broadcast, :is_bot, MapSet.member?(bot_ids, player_id))
          {player_id, broadcast}
        end),
      eliminated_order: state.eliminated_order
    }
  end

  defp broadcast_state(state) do
    payload = build_broadcast_payload(state)

    try do
      TetrisWeb.Endpoint.broadcast(
        "game:#{state.room_id}",
        "game_state",
        payload
      )
    rescue
      _ -> :ok
    end

    bot_payload = build_bot_state_payload(state)

    Enum.each(state.bot_pids, fn {_, pid} ->
      send(pid, {:game_state, bot_payload})
    end)
  end

  defp build_bot_state_payload(state) do
    %{
      status: state.status,
      players:
        Map.new(state.players, fn {player_id, player} ->
          %{
            alive: player.alive,
            score: player.score,
            current_piece: player.current_piece,
            position: player.position,
            next_piece: player.next_piece,
            pieces_placed: player.pieces_placed
          }
          |> then(fn data -> {player_id, data} end)
        end)
    }
  end

  # -- Default targets --

  defp set_default_targets(players, player_order) do
    num_players = length(player_order)

    player_order
    |> Enum.with_index()
    |> Enum.reduce(players, fn {player_id, idx}, acc ->
      next_idx = rem(idx + 1, num_players)
      target_id = Enum.at(player_order, next_idx)
      player = acc[player_id]
      updated_player = %{player | target: target_id}
      Map.put(acc, player_id, updated_player)
    end)
  end

  @impl true
  def terminate(_reason, state) do
    stop_all_bots(state)
    Lobby.remove_room(state.room_id)
    :ok
  end

  # -- Bot cleanup --

  defp stop_all_bots(state) do
    Enum.each(state.bot_pids, fn {_, pid} ->
      try do
        BotSupervisor.stop_bot(pid)
      catch
        _, _ -> :ok
      end
    end)
  end

  # -- Timer --

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end
end
