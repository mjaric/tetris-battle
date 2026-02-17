defmodule TetrisWeb.GameChannel do
  use TetrisWeb, :channel
  alias TetrisGame.GameRoom

  @impl true
  def join("game:" <> room_id, _payload, socket) do
    room = GameRoom.via(room_id)

    do_join(
      room,
      room_id,
      socket.assigns.player_id,
      socket.assigns.nickname,
      socket
    )
  catch
    :exit, _ -> {:error, %{reason: "room_not_found"}}
  end

  defp do_join(room, room_id, player_id, nickname, socket) do
    case GameRoom.join(room, player_id, nickname) do
      :ok ->
        socket = assign(socket, :room_id, room_id)
        send(self(), {:push_state, room})
        {:ok, %{player_id: player_id}, socket}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def handle_info({:push_state, room}, socket) do
    try do
      state = GameRoom.get_state(room)
      push(socket, "game_state", GameRoom.build_broadcast_payload(state))
    catch
      :exit, _ -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("input", %{"action" => action}, socket) do
    room = GameRoom.via(socket.assigns.room_id)
    GameRoom.input(room, socket.assigns.player_id, action)
    {:noreply, socket}
  end

  def handle_in("set_target", %{"target_id" => target_id}, socket) do
    room = GameRoom.via(socket.assigns.room_id)

    case GameRoom.set_target(room, socket.assigns.player_id, target_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("start_game", _payload, socket) do
    room = GameRoom.via(socket.assigns.room_id)

    case GameRoom.start_game(room, socket.assigns.player_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("add_bot", %{"difficulty" => difficulty}, socket) do
    room = GameRoom.via(socket.assigns.room_id)

    diff_atom =
      case difficulty do
        "easy" -> :easy
        "medium" -> :medium
        "hard" -> :hard
        "battle" -> :battle
        _ -> raise ArgumentError, "invalid difficulty: #{difficulty}"
      end

    case GameRoom.add_bot(room, diff_atom) do
      {:ok, bot_id} -> {:reply, {:ok, %{bot_id: bot_id}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  catch
    :exit, _ -> {:reply, {:error, %{reason: "room_not_found"}}, socket}
    :error, %ArgumentError{} -> {:reply, {:error, %{reason: "invalid_difficulty"}}, socket}
  end

  def handle_in("remove_bot", %{"bot_id" => bot_id}, socket) do
    room = GameRoom.via(socket.assigns.room_id)

    case GameRoom.remove_bot(room, bot_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  catch
    :exit, _ -> {:reply, {:error, %{reason: "room_not_found"}}, socket}
  end

  def handle_in("ping", _payload, socket) do
    server_time = System.monotonic_time(:millisecond)
    {:reply, {:ok, %{server_time: server_time}}, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :room_id) do
      room = GameRoom.via(socket.assigns.room_id)

      try do
        GameRoom.leave(room, socket.assigns.player_id)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end
end
