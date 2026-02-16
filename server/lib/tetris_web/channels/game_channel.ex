defmodule TetrisWeb.GameChannel do
  use TetrisWeb, :channel
  alias TetrisGame.GameRoom

  @impl true
  def join("game:" <> room_id, payload, socket) do
    player_id = socket.assigns.player_id
    nickname = socket.assigns.nickname
    room = GameRoom.via(room_id)

    # Try to get room state to check password
    try do
      state = GameRoom.get_state(room)

      case state.password do
        nil ->
          # No password, join directly
          do_join(room, room_id, player_id, nickname, socket)

        stored_pw ->
          # Check for auth challenge-response
          nonce = Map.get(payload, "nonce")
          hmac = Map.get(payload, "hmac")

          if nonce && hmac do
            expected =
              :crypto.mac(:hmac, :sha256, stored_pw, Base.decode64!(nonce)) |> Base.encode64()

            if Plug.Crypto.secure_compare(hmac, expected) do
              do_join(room, room_id, player_id, nickname, socket)
            else
              {:error, %{reason: "invalid_password"}}
            end
          else
            # Send challenge nonce
            challenge_nonce = :crypto.strong_rand_bytes(32) |> Base.encode64()
            {:error, %{reason: "auth_required", nonce: challenge_nonce}}
          end
      end
    catch
      :exit, _ -> {:error, %{reason: "room_not_found"}}
    end
  end

  defp do_join(room, room_id, player_id, nickname, socket) do
    case GameRoom.join(room, player_id, nickname) do
      :ok ->
        socket = assign(socket, :room_id, room_id)
        {:ok, %{player_id: player_id}, socket}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
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
