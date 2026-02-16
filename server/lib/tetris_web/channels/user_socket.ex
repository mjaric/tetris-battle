defmodule TetrisWeb.UserSocket do
  use Phoenix.Socket

  channel "lobby:*", TetrisWeb.LobbyChannel
  channel "game:*", TetrisWeb.GameChannel

  @impl true
  def connect(%{"nickname" => nickname}, socket, _connect_info) do
    player_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    socket = assign(socket, :player_id, player_id)
    socket = assign(socket, :nickname, nickname)
    {:ok, socket}
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.player_id}"
end
