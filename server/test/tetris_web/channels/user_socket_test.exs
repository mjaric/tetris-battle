defmodule TetrisWeb.UserSocketTest do
  use Platform.DataCase, async: true

  alias Platform.Accounts
  alias Platform.Auth.Token
  alias TetrisWeb.UserSocket

  describe "connect/3" do
    test "connects with a valid JWT" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "google",
          provider_id: "socket_test",
          display_name: "SocketUser"
        })

      token = Token.sign(user.id)

      assert {:ok, socket} =
               UserSocket.connect(
                 %{"token" => token},
                 %Phoenix.Socket{},
                 %{}
               )

      assert socket.assigns.user_id == user.id
      assert socket.assigns.player_id == user.id
      assert socket.assigns.nickname == "SocketUser"
    end

    test "rejects invalid token" do
      assert :error =
               UserSocket.connect(
                 %{"token" => "bad_token"},
                 %Phoenix.Socket{},
                 %{}
               )
    end

    test "rejects missing token" do
      assert :error =
               UserSocket.connect(%{}, %Phoenix.Socket{}, %{})
    end

    test "uses nickname when available" do
      {:ok, user} =
        Accounts.register_user(%{
          provider: "google",
          provider_id: "socket_nick_test",
          display_name: "Full Name",
          nickname: "NickUser"
        })

      token = Token.sign(user.id)

      assert {:ok, socket} =
               UserSocket.connect(
                 %{"token" => token},
                 %Phoenix.Socket{},
                 %{}
               )

      assert socket.assigns.nickname == "NickUser"
    end

    test "falls back to display_name for guests without nickname" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "anonymous",
          provider_id: "guest_socket_#{System.unique_integer([:positive])}",
          display_name: "Guest_abc",
          is_anonymous: true
        })

      token = Token.sign(user.id)

      assert {:ok, socket} =
               UserSocket.connect(
                 %{"token" => token},
                 %Phoenix.Socket{},
                 %{}
               )

      assert socket.assigns.nickname == "Guest_abc"
    end

    test "rejects token for deleted user" do
      token = Token.sign(Ecto.UUID.generate())

      assert :error =
               UserSocket.connect(
                 %{"token" => token},
                 %Phoenix.Socket{},
                 %{}
               )
    end
  end
end
