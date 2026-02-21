defmodule PlatformWeb.AuthController do
  use Phoenix.Controller, formats: [:html, :json]
  plug(Ueberauth when action in [:request, :callback])

  alias Platform.Accounts
  alias Platform.Auth.Token

  def callback(
        %{assigns: %{ueberauth_auth: auth}} = conn,
        _params
      ) do
    provider = to_string(auth.provider)
    provider_id = auth.uid
    client_url = Application.get_env(:tetris, :client_url)

    case Accounts.get_user_by_provider(provider, provider_id) do
      %Accounts.User{} = user ->
        token = sign_auth_token(user)

        redirect(conn,
          external: "#{client_url}/oauth/callback#token=#{token}"
        )

      nil ->
        reg_token =
          Token.sign_registration(%{
            provider: provider,
            provider_id: provider_id,
            name: auth.info.name || auth.info.email || "Player",
            email: auth.info.email,
            avatar_url: auth.info.image
          })

        redirect(conn,
          external:
            "#{client_url}/oauth/callback" <>
              "#registration_token=#{reg_token}"
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

  def register(conn, params) do
    with {:ok, reg_data} <-
           Token.verify_registration(params["registration_token"]),
         {:ok, user} <- do_register(reg_data, params) do
      token = sign_auth_token(user)

      json(conn, %{
        token: token,
        user: %{
          id: user.id,
          nickname: user.nickname,
          display_name: user.display_name
        }
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_registration_token"})

      {:error, :token_expired} ->
        conn
        |> put_status(401)
        |> json(%{error: "registration_token_expired"})

      {:error, :not_anonymous} ->
        conn
        |> put_status(422)
        |> json(%{errors: %{guest: "not a guest account"}})

      {:error, :invalid_guest_token} ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_guest_token"})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)
        conn |> put_status(422) |> json(%{errors: errors})
    end
  end

  def check_nickname(conn, %{"nickname" => nickname}) do
    nickname_regex = ~r/^[a-zA-Z][a-zA-Z0-9_]{2,19}$/

    cond do
      not Regex.match?(nickname_regex, nickname) ->
        json(conn, %{
          available: false,
          nickname: nickname,
          reason: "invalid_format"
        })

      Accounts.nickname_available?(nickname) ->
        json(conn, %{available: true, nickname: nickname})

      true ->
        json(conn, %{
          available: false,
          nickname: nickname,
          reason: "taken"
        })
    end
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
        token = sign_auth_token(user)

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
      new_token = sign_auth_token(user)
      json(conn, %{token: new_token})
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_token"})
    end
  end

  defp do_register(reg_data, %{"guest_token" => guest_token} = params)
       when is_binary(guest_token) and guest_token != "" do
    with {:ok, guest_id} <- Token.verify(guest_token),
         %Accounts.User{is_anonymous: true} = guest <-
           Accounts.get_user(guest_id) do
      Accounts.register_guest_upgrade(guest, %{
        provider: reg_data.provider,
        provider_id: reg_data.provider_id,
        display_name: params["display_name"] || reg_data.name,
        email: reg_data.email,
        avatar_url: reg_data.avatar_url,
        nickname: params["nickname"],
        is_anonymous: false
      })
    else
      {:error, _} -> {:error, :invalid_guest_token}
      nil -> {:error, :invalid_guest_token}
      %Accounts.User{is_anonymous: false} -> {:error, :not_anonymous}
    end
  end

  defp do_register(reg_data, params) do
    Accounts.register_user(%{
      provider: reg_data.provider,
      provider_id: reg_data.provider_id,
      display_name: params["display_name"] || reg_data.name,
      email: reg_data.email,
      avatar_url: reg_data.avatar_url,
      nickname: params["nickname"]
    })
  end

  defp sign_auth_token(user) do
    Token.sign(user.id,
      claims: %{
        "name" => user.display_name,
        "nickname" => user.nickname
      }
    )
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
