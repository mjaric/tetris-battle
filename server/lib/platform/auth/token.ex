defmodule Platform.Auth.Token do
  @moduledoc """
  JWT token signing and verification using HS256.

  Keys are derived from Phoenix's `secret_key_base` via
  HMAC-SHA256 with a dedicated purpose string, keeping
  JWT signing material separate from the general secret.
  """

  @default_ttl 3600

  @doc """
  Signs a JWT containing the given `user_id` as the `sub` claim.

  Options:
    * `:ttl` - time-to-live in seconds (default: #{@default_ttl})
  """
  @spec sign(String.t(), keyword()) :: String.t()
  def sign(user_id, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    extra = Keyword.get(opts, :claims, %{})
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{"sub" => user_id, "iat" => now, "exp" => now + ttl},
        extra
      )

    jwk = signing_key()
    jws = JOSE.JWS.from_map(%{"alg" => "HS256"})
    jwt = JOSE.JWT.from_map(claims)

    {_, token} =
      jwk
      |> JOSE.JWT.sign(jws, jwt)
      |> JOSE.JWS.compact()

    token
  end

  @doc """
  Verifies a JWT and returns the `sub` claim (user_id).

  Returns `{:ok, user_id}` on success, or
  `{:error, :invalid_token}` / `{:error, :token_expired}` on failure.
  """
  @spec verify(String.t() | nil) ::
          {:ok, String.t()} | {:error, :invalid_token | :token_expired}
  def verify(token) when is_binary(token) do
    jwk = signing_key()

    case JOSE.JWT.verify(jwk, token) do
      {true, %JOSE.JWT{fields: claims}, _jws} ->
        validate_expiry(claims)

      _invalid ->
        {:error, :invalid_token}
    end
  rescue
    _exception -> {:error, :invalid_token}
  end

  def verify(_not_binary), do: {:error, :invalid_token}

  defp validate_expiry(claims) do
    now = System.system_time(:second)
    exp = Map.get(claims, "exp", 0)

    if exp > now do
      {:ok, claims["sub"]}
    else
      {:error, :token_expired}
    end
  end

  defp signing_key do
    secret =
      Application.get_env(:tetris, TetrisWeb.Endpoint)[:secret_key_base]

    derived =
      :crypto.mac(:hmac, :sha256, secret, "platform_jwt_signing")

    JOSE.JWK.from_oct(derived)
  end
end
