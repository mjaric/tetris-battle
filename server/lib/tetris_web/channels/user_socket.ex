defmodule TetrisWeb.UserSocket do
  use Phoenix.Socket

  alias Platform.Accounts
  alias Platform.Auth.Token

  channel("lobby:*", TetrisWeb.LobbyChannel)
  channel("game:*", TetrisWeb.GameChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, user_id} <- Token.verify(token),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      socket =
        socket
        |> assign(:user_id, user.id)
        |> assign(:player_id, user.id)
        |> assign(:nickname, user.nickname || user.display_name)

      {:ok, socket}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
