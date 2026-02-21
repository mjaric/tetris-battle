defmodule PlatformWeb.AuthController do
  use Phoenix.Controller, formats: [:html, :json]
  plug(Ueberauth when action in [:request, :callback])

  alias Platform.Accounts
  alias Platform.Auth.Token

  def callback(
        %{assigns: %{ueberauth_auth: auth}} = conn,
        _params
      ) do
    user_attrs = %{
      provider: to_string(auth.provider),
      provider_id: auth.uid,
      email: auth.info.email,
      display_name: auth.info.name || auth.info.email || "Player",
      avatar_url: auth.info.image
    }

    case Accounts.find_or_create_user(user_attrs) do
      {:ok, user} ->
        token = Token.sign(user.id, claims: %{"name" => user.display_name})
        client_url = Application.get_env(:tetris, :client_url)

        redirect(conn,
          external: "#{client_url}/oauth/callback#token=#{token}"
        )

      {:error, _changeset} ->
        client_url = Application.get_env(:tetris, :client_url)

        redirect(conn,
          external: "#{client_url}/oauth/callback?error=account_creation_failed"
        )
    end
  end

  def callback(
        %{assigns: %{ueberauth_failure: failure}} = conn,
        _params
      ) do
    reason = Enum.map_join(failure.errors, ", ", & &1.message)

    client_url = Application.get_env(:tetris, :client_url)

    redirect(conn,
      external: "#{client_url}/oauth/callback?error=#{URI.encode(reason)}"
    )
  end

  def guest(conn, _params) do
    guest_id = Ecto.UUID.generate()

    case Accounts.create_user(%{
           provider: "anonymous",
           provider_id: guest_id,
           display_name: "Guest_#{String.slice(guest_id, 0..5)}",
           is_anonymous: true
         }) do
      {:ok, user} ->
        token = Token.sign(user.id, claims: %{"name" => user.display_name})

        json(conn, %{
          token: token,
          user: %{id: user.id, display_name: user.display_name}
        })

      {:error, _changeset} ->
        conn
        |> put_status(500)
        |> json(%{error: "account_creation_failed"})
    end
  end

  def refresh(conn, _params) do
    with ["Bearer " <> token] <-
           get_req_header(conn, "authorization"),
         {:ok, user_id} <- Token.verify(token),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      new_token = Token.sign(user_id, claims: %{"name" => user.display_name})
      json(conn, %{token: new_token})
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_token"})
    end
  end
end
