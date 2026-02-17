defmodule TetrisWeb.LobbyChannel do
  @moduledoc false
  use TetrisWeb, :channel
  alias TetrisGame.GameRoom
  alias TetrisGame.Lobby

  @impl true
  def join("lobby:main", _payload, socket) do
    {:ok, %{player_id: socket.assigns.player_id}, socket}
  end

  @impl true
  def handle_in("list_rooms", _payload, socket) do
    rooms = Lobby.list_rooms()
    {:reply, {:ok, %{rooms: rooms}}, socket}
  end

  def handle_in("create_room", payload, socket) do
    opts = %{
      host: socket.assigns.player_id,
      name: Map.get(payload, "name", "Unnamed Room"),
      max_players: Map.get(payload, "max_players", 4)
    }

    case Lobby.create_room(opts) do
      {:ok, room_id} ->
        room = GameRoom.via(room_id)
        nickname = Map.get(socket.assigns, :nickname, "Host")
        GameRoom.join(room, socket.assigns.player_id, nickname)
        Lobby.update_room(room_id, %{player_count: 1})

        broadcast!(
          socket,
          "room_created",
          %{room_id: room_id, name: opts.name}
        )

        {:reply, {:ok, %{room_id: room_id, is_host: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end
end
