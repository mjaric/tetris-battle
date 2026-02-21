# Registration & Nickname — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a registration step with unique nicknames to the OAuth flow, so new users pick a public handle before playing, and guests can upgrade to full accounts.

**Architecture:** OAuth callback no longer auto-creates users. Instead, for new users it issues a short-lived "registration JWT" containing the OAuth data. The client detects this token type, shows a registration form (pre-filled name, blank nickname with live availability check), and POSTs back to complete registration. Guest upgrade sends both the registration token and the existing guest JWT. A new `nickname` column on `users` stores the unique public handle.

**Tech Stack:** Ecto migration (PostgreSQL), JOSE JWT, Phoenix controllers, React (AuthProvider context, RegisterPage component)

**Design doc:** `docs/plans/2026-02-21-registration-nickname-design.md`

**Depends on:** Auth & Registration (completed, commit `dd931d0`)

---

## Task 1: Migration — Add Nickname Column

**Files:**
- Create: `server/priv/repo/migrations/*_add_nickname_to_users.exs`

**Step 1: Generate migration**

Run:
```bash
cd server && mix ecto.gen.migration add_nickname_to_users
```

**Step 2: Write the migration**

Edit the generated file in `server/priv/repo/migrations/`:

```elixir
defmodule Platform.Repo.Migrations.AddNicknameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :nickname, :text
    end

    create unique_index(:users, [:nickname])

    create constraint(:users, :nickname_format,
      check: "nickname ~ '^[a-zA-Z][a-zA-Z0-9_]{2,19}$'"
    )
  end
end
```

**Step 3: Run migration**

Run:
```bash
cd server && mix ecto.migrate
```

Expected: Migration runs successfully.

**Step 4: Verify in test env**

Run:
```bash
cd server && MIX_ENV=test mix ecto.migrate
cd server && mix test
```

Expected: All existing tests still pass (nickname is nullable, no existing code touches it).

**Step 5: Commit**

```bash
git add server/priv/repo/migrations/*_add_nickname_to_users.exs
git commit -m "feat: add nickname column to users table"
```

---

## Task 2: User Schema — Add Nickname Field and Registration Changeset

**Files:**
- Modify: `server/lib/platform/accounts/user.ex`
- Modify: `server/test/platform/accounts_test.exs`

**Step 1: Write the failing tests**

Add to `server/test/platform/accounts_test.exs`, after the existing `describe` blocks:

```elixir
describe "registration_changeset/2" do
  test "valid nickname" do
    user = %User{}

    changeset =
      User.registration_changeset(user, %{
        provider: "google",
        provider_id: "reg_1",
        display_name: "Test User",
        nickname: "TestNick"
      })

    assert changeset.valid?
    assert get_change(changeset, :nickname) == "TestNick"
  end

  test "rejects nickname shorter than 3 chars" do
    changeset =
      User.registration_changeset(%User{}, %{
        provider: "google",
        provider_id: "reg_2",
        display_name: "Test",
        nickname: "ab"
      })

    refute changeset.valid?
    assert errors_on(changeset)[:nickname]
  end

  test "rejects nickname longer than 20 chars" do
    changeset =
      User.registration_changeset(%User{}, %{
        provider: "google",
        provider_id: "reg_3",
        display_name: "Test",
        nickname: String.duplicate("a", 21)
      })

    refute changeset.valid?
    assert errors_on(changeset)[:nickname]
  end

  test "rejects nickname starting with a digit" do
    changeset =
      User.registration_changeset(%User{}, %{
        provider: "google",
        provider_id: "reg_4",
        display_name: "Test",
        nickname: "1BadNick"
      })

    refute changeset.valid?
    assert errors_on(changeset)[:nickname]
  end

  test "rejects nickname with special characters" do
    changeset =
      User.registration_changeset(%User{}, %{
        provider: "google",
        provider_id: "reg_5",
        display_name: "Test",
        nickname: "bad-nick!"
      })

    refute changeset.valid?
    assert errors_on(changeset)[:nickname]
  end

  test "accepts nickname with underscores" do
    changeset =
      User.registration_changeset(%User{}, %{
        provider: "google",
        provider_id: "reg_6",
        display_name: "Test",
        nickname: "good_nick_1"
      })

    assert changeset.valid?
  end

  test "requires nickname" do
    changeset =
      User.registration_changeset(%User{}, %{
        provider: "google",
        provider_id: "reg_7",
        display_name: "Test"
      })

    refute changeset.valid?
    assert errors_on(changeset)[:nickname]
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/platform/accounts_test.exs -v
```

Expected: FAIL — `registration_changeset/2` not defined.

**Step 3: Add nickname field and registration_changeset to User schema**

Replace `server/lib/platform/accounts/user.ex`:

```elixir
defmodule Platform.Accounts.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @nickname_format ~r/^[a-zA-Z][a-zA-Z0-9_]{2,19}$/

  schema "users" do
    field(:provider, :string)
    field(:provider_id, :string)
    field(:email, :string)
    field(:display_name, :string)
    field(:nickname, :string)
    field(:avatar_url, :string)
    field(:is_anonymous, :boolean, default: false)
    field(:settings, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  @required_fields [:provider, :provider_id, :display_name]
  @optional_fields [
    :email,
    :avatar_url,
    :is_anonymous,
    :settings,
    :nickname
  ]

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:provider, :provider_id])
    |> maybe_validate_nickname()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required([:provider, :provider_id, :display_name, :nickname])
    |> validate_nickname()
  end

  defp validate_nickname(changeset) do
    changeset
    |> validate_format(:nickname, @nickname_format,
      message: "must start with a letter, 3-20 chars, letters/digits/underscores only"
    )
    |> unique_constraint(:nickname)
  end

  defp maybe_validate_nickname(changeset) do
    if get_change(changeset, :nickname) do
      validate_nickname(changeset)
    else
      changeset
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform/accounts_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add server/lib/platform/accounts/user.ex \
  server/test/platform/accounts_test.exs
git commit -m "feat: add nickname field and registration_changeset to User"
```

---

## Task 3: Accounts Context — Register User and Check Nickname

**Files:**
- Modify: `server/lib/platform/accounts.ex`
- Modify: `server/test/platform/accounts_test.exs`

**Step 1: Write the failing tests**

Add to `server/test/platform/accounts_test.exs`:

```elixir
describe "register_user/1" do
  test "creates a user with nickname" do
    attrs = %{
      provider: "google",
      provider_id: "reg_new_1",
      display_name: "New User",
      email: "new@example.com",
      nickname: "NewPlayer"
    }

    assert {:ok, %User{} = user} = Accounts.register_user(attrs)
    assert user.nickname == "NewPlayer"
    assert user.display_name == "New User"
    assert user.is_anonymous == false
  end

  test "fails with duplicate nickname" do
    base = %{
      provider: "google",
      provider_id: "reg_dup_1",
      display_name: "User1",
      nickname: "TakenNick"
    }

    assert {:ok, _} = Accounts.register_user(base)

    assert {:error, changeset} =
             Accounts.register_user(%{
               base
               | provider_id: "reg_dup_2",
                 display_name: "User2"
             })

    assert errors_on(changeset)[:nickname]
  end

  test "fails with invalid nickname format" do
    assert {:error, changeset} =
             Accounts.register_user(%{
               provider: "google",
               provider_id: "reg_bad",
               display_name: "Bad",
               nickname: "1bad"
             })

    assert errors_on(changeset)[:nickname]
  end
end

describe "register_guest_upgrade/2" do
  test "upgrades anonymous user with nickname" do
    {:ok, anon} =
      Accounts.create_user(%{
        provider: "anonymous",
        provider_id: Ecto.UUID.generate(),
        display_name: "Guest_abc",
        is_anonymous: true
      })

    upgrade_attrs = %{
      provider: "google",
      provider_id: "google_upgrade_1",
      display_name: "Real Name",
      email: "real@example.com",
      nickname: "RealPlayer",
      is_anonymous: false
    }

    assert {:ok, upgraded} =
             Accounts.register_guest_upgrade(anon, upgrade_attrs)

    assert upgraded.id == anon.id
    assert upgraded.nickname == "RealPlayer"
    assert upgraded.provider == "google"
    assert upgraded.is_anonymous == false
  end

  test "rejects upgrade for non-anonymous user" do
    {:ok, user} =
      Accounts.register_user(%{
        provider: "google",
        provider_id: "not_anon_1",
        display_name: "NotAnon",
        nickname: "NotAnon"
      })

    assert {:error, :not_anonymous} =
             Accounts.register_guest_upgrade(user, %{
               nickname: "NewNick"
             })
  end
end

describe "nickname_available?/1" do
  test "returns true for available nickname" do
    assert Accounts.nickname_available?("FreshNick")
  end

  test "returns false for taken nickname" do
    Accounts.register_user(%{
      provider: "google",
      provider_id: "taken_1",
      display_name: "Taken",
      nickname: "TakenName"
    })

    refute Accounts.nickname_available?("TakenName")
  end

  test "returns false for invalid format" do
    refute Accounts.nickname_available?("1bad")
  end

  test "returns false for too short" do
    refute Accounts.nickname_available?("ab")
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/platform/accounts_test.exs -v
```

Expected: FAIL — functions not defined.

**Step 3: Implement register_user, register_guest_upgrade, nickname_available?**

Replace `server/lib/platform/accounts.ex`:

```elixir
defmodule Platform.Accounts do
  @moduledoc false
  import Ecto.Query
  alias Platform.Accounts.User
  alias Platform.Repo

  @nickname_format ~r/^[a-zA-Z][a-zA-Z0-9_]{2,19}$/

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_provider(provider, provider_id) do
    Repo.get_by(User, provider: provider, provider_id: provider_id)
  end

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def find_or_create_user(attrs) do
    changeset = User.changeset(%User{}, attrs)

    Repo.insert(
      changeset,
      on_conflict: [set: [updated_at: DateTime.utc_now()]],
      conflict_target: [:provider, :provider_id],
      returning: true
    )
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def register_guest_upgrade(
        %User{is_anonymous: true} = user,
        attrs
      ) do
    user
    |> User.registration_changeset(attrs)
    |> Repo.update()
  end

  def register_guest_upgrade(%User{is_anonymous: false}, _attrs) do
    {:error, :not_anonymous}
  end

  def nickname_available?(nickname) do
    Regex.match?(@nickname_format, nickname) and
      not Repo.exists?(
        from(u in User, where: u.nickname == ^nickname)
      )
  end

  def upgrade_anonymous_user(%User{is_anonymous: true} = user, attrs) do
    update_user(user, attrs)
  end

  def upgrade_anonymous_user(%User{is_anonymous: false} = user, _attrs) do
    {:ok, user}
  end

  def search_users_by_name(query_string, limit \\ 20) do
    sanitized =
      query_string
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    pattern = "%#{sanitized}%"

    User
    |> where([u], ilike(u.display_name, ^pattern))
    |> where([u], u.is_anonymous == false)
    |> limit(^limit)
    |> Repo.all()
  end
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform/accounts_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add server/lib/platform/accounts.ex \
  server/test/platform/accounts_test.exs
git commit -m "feat: add register_user, register_guest_upgrade, nickname_available?"
```

---

## Task 4: Token Module — Registration Token Signing and Verification

**Files:**
- Modify: `server/lib/platform/auth/token.ex`
- Modify: `server/test/platform/auth/token_test.exs`

**Step 1: Write the failing tests**

Add to `server/test/platform/auth/token_test.exs`:

```elixir
describe "sign_registration/1 and verify_registration/1" do
  @registration_data %{
    provider: "google",
    provider_id: "google_123",
    name: "John Smith",
    email: "john@example.com",
    avatar_url: "https://example.com/photo.jpg"
  }

  test "round-trips registration data" do
    token = Token.sign_registration(@registration_data)
    assert {:ok, data} = Token.verify_registration(token)
    assert data.provider == "google"
    assert data.provider_id == "google_123"
    assert data.name == "John Smith"
    assert data.email == "john@example.com"
    assert data.avatar_url == "https://example.com/photo.jpg"
  end

  test "rejects expired registration token" do
    token = Token.sign_registration(@registration_data, ttl: -1)
    assert {:error, :token_expired} = Token.verify_registration(token)
  end

  test "rejects tampered registration token" do
    token = Token.sign_registration(@registration_data)
    assert {:error, :invalid_token} = Token.verify_registration(token <> "x")
  end

  test "verify_registration rejects a normal auth token" do
    token = Token.sign(@test_user_id)
    assert {:error, :invalid_token} = Token.verify_registration(token)
  end

  test "verify rejects a registration token" do
    token = Token.sign_registration(@registration_data)
    assert {:error, :invalid_token} = Token.verify(token)
  end

  test "handles nil email and avatar_url" do
    data = %{@registration_data | email: nil, avatar_url: nil}
    token = Token.sign_registration(data)
    assert {:ok, decoded} = Token.verify_registration(token)
    assert decoded.email == nil
    assert decoded.avatar_url == nil
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/platform/auth/token_test.exs -v
```

Expected: FAIL — functions not defined.

**Step 3: Add sign_registration and verify_registration**

Add the following functions to `server/lib/platform/auth/token.ex`, before the `defp` functions at the bottom:

```elixir
@registration_ttl 600

@spec sign_registration(map(), keyword()) :: String.t()
def sign_registration(data, opts \\ []) do
  ttl = Keyword.get(opts, :ttl, @registration_ttl)
  now = System.system_time(:second)

  claims = %{
    "type" => "registration",
    "provider" => data.provider,
    "provider_id" => data.provider_id,
    "name" => data.name,
    "email" => data[:email],
    "avatar_url" => data[:avatar_url],
    "iat" => now,
    "exp" => now + ttl
  }

  jwk = signing_key()
  jws = JOSE.JWS.from_map(%{"alg" => "HS256"})
  jwt = JOSE.JWT.from_map(claims)

  {_, token} =
    jwk
    |> JOSE.JWT.sign(jws, jwt)
    |> JOSE.JWS.compact()

  token
end

@spec verify_registration(String.t() | nil) ::
        {:ok, map()} | {:error, :invalid_token | :token_expired}
def verify_registration(token) when is_binary(token) do
  jwk = signing_key()

  case JOSE.JWT.verify(jwk, token) do
    {true, %JOSE.JWT{fields: %{"type" => "registration"} = claims}, _jws} ->
      now = System.system_time(:second)
      exp = Map.get(claims, "exp", 0)

      if exp > now do
        {:ok,
         %{
           provider: claims["provider"],
           provider_id: claims["provider_id"],
           name: claims["name"],
           email: claims["email"],
           avatar_url: claims["avatar_url"]
         }}
      else
        {:error, :token_expired}
      end

    _invalid ->
      {:error, :invalid_token}
  end
rescue
  _exception -> {:error, :invalid_token}
end

def verify_registration(_not_binary), do: {:error, :invalid_token}
```

Also update the existing `verify/1` to reject registration tokens. Change the `validate_expiry` call to check for `type`:

In the `verify/1` function, change the success case from:

```elixir
{true, %JOSE.JWT{fields: claims}, _jws} ->
  validate_expiry(claims)
```

to:

```elixir
{true, %JOSE.JWT{fields: %{"type" => "registration"}}, _jws} ->
  {:error, :invalid_token}

{true, %JOSE.JWT{fields: claims}, _jws} ->
  validate_expiry(claims)
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform/auth/token_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add server/lib/platform/auth/token.ex \
  server/test/platform/auth/token_test.exs
git commit -m "feat: add registration token signing and verification"
```

---

## Task 5: AuthController — Registration Endpoint and Callback Split

**Files:**
- Modify: `server/lib/platform_web/controllers/auth_controller.ex`
- Modify: `server/lib/tetris_web/router.ex`
- Modify: `server/test/platform_web/controllers/auth_controller_test.exs`

**Step 1: Write the failing tests**

Add to `server/test/platform_web/controllers/auth_controller_test.exs`:

```elixir
describe "GET /auth/:provider/callback (new user)" do
  test "redirects with registration_token for new user", %{conn: conn} do
    auth = %Ueberauth.Auth{
      uid: "brand_new_uid",
      provider: :google,
      info: %Ueberauth.Auth.Info{
        name: "Brand New User",
        email: "brandnew@example.com",
        image: "https://example.com/new.jpg"
      }
    }

    conn =
      conn
      |> assign(:ueberauth_auth, auth)
      |> get("/auth/google/callback")

    location = redirected_to(conn)
    assert location =~ "registration_token="
    refute location =~ "#token="
  end
end

describe "POST /api/auth/register" do
  test "creates user from registration token", %{conn: conn} do
    reg_token =
      Platform.Auth.Token.sign_registration(%{
        provider: "google",
        provider_id: "register_test_1",
        name: "Reg User",
        email: "reg@example.com",
        avatar_url: nil
      })

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/register", %{
        "registration_token" => reg_token,
        "nickname" => "RegPlayer",
        "display_name" => "Reg User"
      })

    body = json_response(conn, 200)
    assert body["token"]
    assert body["user"]["nickname"] == "RegPlayer"
    assert body["user"]["display_name"] == "Reg User"

    assert {:ok, user_id} = Platform.Auth.Token.verify(body["token"])
    user = Platform.Accounts.get_user(user_id)
    assert user.nickname == "RegPlayer"
  end

  test "upgrades guest user when guest_token provided", %{conn: conn} do
    # Create a guest first
    guest_conn = post(conn, "/api/auth/guest")
    %{"token" => guest_token} = json_response(guest_conn, 200)

    reg_token =
      Platform.Auth.Token.sign_registration(%{
        provider: "github",
        provider_id: "guest_upgrade_1",
        name: "Upgraded User",
        email: "upgraded@example.com",
        avatar_url: nil
      })

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/register", %{
        "registration_token" => reg_token,
        "nickname" => "UpgradedPlayer",
        "display_name" => "Upgraded User",
        "guest_token" => guest_token
      })

    body = json_response(conn, 200)
    assert body["token"]
    assert body["user"]["nickname"] == "UpgradedPlayer"

    # Verify it's the same user record (upgraded, not new)
    {:ok, guest_id} = Platform.Auth.Token.verify(guest_token)
    {:ok, new_id} = Platform.Auth.Token.verify(body["token"])
    assert new_id == guest_id
  end

  test "returns 401 for invalid registration token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/register", %{
        "registration_token" => "invalid",
        "nickname" => "Test",
        "display_name" => "Test"
      })

    assert json_response(conn, 401)["error"]
  end

  test "returns 422 for invalid nickname", %{conn: conn} do
    reg_token =
      Platform.Auth.Token.sign_registration(%{
        provider: "google",
        provider_id: "bad_nick_test",
        name: "Test",
        email: nil,
        avatar_url: nil
      })

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/register", %{
        "registration_token" => reg_token,
        "nickname" => "1bad",
        "display_name" => "Test"
      })

    assert json_response(conn, 422)["errors"]
  end

  test "returns 422 for duplicate nickname", %{conn: conn} do
    Platform.Accounts.register_user(%{
      provider: "google",
      provider_id: "dup_nick_existing",
      display_name: "Existing",
      nickname: "DupNick"
    })

    reg_token =
      Platform.Auth.Token.sign_registration(%{
        provider: "google",
        provider_id: "dup_nick_new",
        name: "New",
        email: nil,
        avatar_url: nil
      })

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/register", %{
        "registration_token" => reg_token,
        "nickname" => "DupNick",
        "display_name" => "New"
      })

    assert json_response(conn, 422)["errors"]
  end
end

describe "GET /api/auth/check-nickname/:nickname" do
  test "returns available for unused nickname", %{conn: conn} do
    conn = get(conn, "/api/auth/check-nickname/FreshNick")
    body = json_response(conn, 200)
    assert body["available"] == true
    assert body["nickname"] == "FreshNick"
  end

  test "returns unavailable for taken nickname", %{conn: conn} do
    Platform.Accounts.register_user(%{
      provider: "google",
      provider_id: "check_taken_1",
      display_name: "Taken",
      nickname: "TakenCheck"
    })

    conn = get(conn, "/api/auth/check-nickname/TakenCheck")
    body = json_response(conn, 200)
    assert body["available"] == false
    assert body["reason"] == "taken"
  end

  test "returns unavailable for invalid format", %{conn: conn} do
    conn = get(conn, "/api/auth/check-nickname/1bad")
    body = json_response(conn, 200)
    assert body["available"] == false
    assert body["reason"] == "invalid_format"
  end
end
```

Also update the existing callback test. The test at line 52 `"redirects to client with JWT on success"` currently expects `#token=` for any callback. This test creates a new user (brand new `uid`), so after our change it should receive a `registration_token`. We need to update it:

Change the existing `"redirects to client with JWT on success"` test. We need to pre-create the user so the callback finds an existing user and returns a normal JWT:

```elixir
test "redirects to client with JWT for existing user", %{conn: conn} do
  # Pre-create the user so callback finds them
  Platform.Accounts.register_user(%{
    provider: "google",
    provider_id: "google_test_uid",
    display_name: "Test User",
    nickname: "TestExisting"
  })

  auth = %Ueberauth.Auth{
    uid: "google_test_uid",
    provider: :google,
    info: %Ueberauth.Auth.Info{
      name: "Test User",
      email: "test@example.com",
      image: "https://example.com/photo.jpg"
    }
  }

  conn =
    conn
    |> assign(:ueberauth_auth, auth)
    |> get("/auth/google/callback")

  assert redirected_to(conn) =~
           "http://localhost:4000/oauth/callback#token="
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/platform_web/controllers/auth_controller_test.exs -v
```

Expected: FAIL — new actions not defined, old test may fail.

**Step 3: Add routes to router**

In `server/lib/tetris_web/router.ex`, add to the `/api/auth` scope:

```elixir
post("/register", AuthController, :register)
get("/check-nickname/:nickname", AuthController, :check_nickname)
```

So the scope becomes:

```elixir
scope "/api/auth", PlatformWeb do
  pipe_through(:api)

  post("/guest", AuthController, :guest)
  post("/refresh", AuthController, :refresh)
  post("/register", AuthController, :register)
  get("/check-nickname/:nickname", AuthController, :check_nickname)
end
```

**Step 4: Rewrite AuthController**

Replace `server/lib/platform_web/controllers/auth_controller.ex`:

```elixir
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
        redirect(conn, external: "#{client_url}/oauth/callback#token=#{token}")

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
          external: "#{client_url}/oauth/callback#registration_token=#{reg_token}"
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
        conn |> put_status(401) |> json(%{error: "invalid_registration_token"})

      {:error, :token_expired} ->
        conn |> put_status(401) |> json(%{error: "registration_token_expired"})

      {:error, :not_anonymous} ->
        conn |> put_status(422) |> json(%{errors: %{guest: "not a guest account"}})

      {:error, :invalid_guest_token} ->
        conn |> put_status(401) |> json(%{error: "invalid_guest_token"})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)
        conn |> put_status(422) |> json(%{errors: errors})
    end
  end

  def check_nickname(conn, %{"nickname" => nickname}) do
    cond do
      not Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_]{2,19}$/, nickname) ->
        json(conn, %{available: false, nickname: nickname, reason: "invalid_format"})

      Accounts.nickname_available?(nickname) ->
        json(conn, %{available: true, nickname: nickname})

      true ->
        json(conn, %{available: false, nickname: nickname, reason: "taken"})
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
      claims: %{"name" => user.display_name, "nickname" => user.nickname}
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
```

**Step 5: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform_web/controllers/auth_controller_test.exs -v
cd server && mix test
```

Expected: All tests pass. Fix any issues.

**Step 6: Run format and lint**

Run:
```bash
cd server && mix format
cd server && mix credo --strict
```

Expected: No issues.

**Step 7: Commit**

```bash
git add server/lib/platform_web/controllers/auth_controller.ex \
  server/lib/tetris_web/router.ex \
  server/test/platform_web/controllers/auth_controller_test.exs
git commit -m "feat: add registration endpoint, check-nickname, split OAuth callback"
```

---

## Task 6: UserSocket — Use Nickname for Public Identity

**Files:**
- Modify: `server/lib/tetris_web/channels/user_socket.ex`
- Modify: `server/test/tetris_web/channels/user_socket_test.exs`

**Step 1: Write the failing test**

Add to `server/test/tetris_web/channels/user_socket_test.exs`:

```elixir
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
```

**Step 2: Run tests to verify the first one fails**

Run:
```bash
cd server && mix test test/tetris_web/channels/user_socket_test.exs -v
```

Expected: `"uses nickname when available"` FAILS (assigns `display_name` instead of `nickname`).

**Step 3: Update UserSocket**

Replace `server/lib/tetris_web/channels/user_socket.ex`:

```elixir
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
```

**Step 4: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/tetris_web/channels/user_socket_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add server/lib/tetris_web/channels/user_socket.ex \
  server/test/tetris_web/channels/user_socket_test.exs
git commit -m "feat: use nickname for socket identity, fallback to display_name"
```

---

## Task 7: Client — AuthProvider Registration Token Support

**Files:**
- Modify: `client/src/platform/auth/AuthProvider.tsx`

**Step 1: Update AuthUser interface and add registration state**

In `client/src/platform/auth/AuthProvider.tsx`, make these changes:

Update the `AuthUser` interface:

```typescript
interface AuthUser {
  id: string;
  displayName: string;
  nickname: string | null;
}
```

Add registration types:

```typescript
interface RegistrationData {
  provider: string;
  providerId: string;
  name: string;
  email: string | null;
  avatarUrl: string | null;
}
```

Add to `AuthContextValue`:

```typescript
interface AuthContextValue {
  user: AuthUser | null;
  token: string | null;
  loading: boolean;
  isAuthenticated: boolean;
  registrationToken: string | null;
  registrationData: RegistrationData | null;
  setToken: (token: string | null) => void;
  setRegistrationToken: (token: string | null) => void;
  logout: () => void;
  refreshToken: () => Promise<void>;
}
```

Add state inside `AuthProvider`:

```typescript
const [registrationToken, setRegTokenState] = useState<string | null>(null);
const [registrationData, setRegistrationData] = useState<RegistrationData | null>(null);
```

Add `setRegistrationToken` callback:

```typescript
const setRegistrationToken = useCallback((regToken: string | null) => {
  setRegTokenState(regToken);
  if (regToken) {
    const payload = decodeJwtPayload(regToken);
    if (payload && payload['type'] === 'registration') {
      setRegistrationData({
        provider: payload['provider'] as string,
        providerId: payload['provider_id'] as string,
        name: (payload['name'] as string) ?? '',
        email: (payload['email'] as string) ?? null,
        avatarUrl: (payload['avatar_url'] as string) ?? null,
      });
    }
  } else {
    setRegistrationData(null);
  }
}, []);
```

Update the JWT decode `useEffect` to extract `nickname`:

```typescript
useEffect(() => {
  if (!token) {
    setUser(null);
    return;
  }

  const payload = decodeJwtPayload(token);
  if (payload && typeof payload['sub'] === 'string') {
    setUser({
      id: payload['sub'],
      displayName: (payload['name'] as string) ?? 'Player',
      nickname: (payload['nickname'] as string) ?? null,
    });
  }
}, [token]);
```

Add `registrationToken`, `registrationData`, and `setRegistrationToken` to the context value memo.

**Step 2: Verify client builds**

Run:
```bash
cd client && npm run build
```

Expected: Build succeeds. Fix any type errors.

**Step 3: Commit**

```bash
git add client/src/platform/auth/AuthProvider.tsx
git commit -m "feat: add registration token and nickname to auth context"
```

---

## Task 8: Client — AuthCallback Registration Token Handling

**Files:**
- Modify: `client/src/platform/auth/AuthCallback.tsx`

**Step 1: Update AuthCallback to handle registration_token**

Replace `client/src/platform/auth/AuthCallback.tsx`:

```tsx
import { useEffect } from 'react';
import { useNavigate } from 'react-router';
import { useAuthContext } from './AuthProvider.tsx';

export default function AuthCallback() {
  const navigate = useNavigate();
  const { setToken, setRegistrationToken } = useAuthContext();

  useEffect(() => {
    const hash = window.location.hash;
    const params = new URLSearchParams(window.location.search);

    if (hash.startsWith('#token=')) {
      const token = hash.slice('#token='.length);
      setToken(token);
      window.history.replaceState(null, '', '/oauth/callback');
      navigate('/', { replace: true });
      return;
    }

    if (hash.startsWith('#registration_token=')) {
      const regToken = hash.slice('#registration_token='.length);
      setRegistrationToken(regToken);
      window.history.replaceState(null, '', '/oauth/callback');
      navigate('/register', { replace: true });
      return;
    }

    const error = params.get('error');
    if (error) {
      console.error('Auth error:', error);
    }

    navigate('/login', { replace: true });
  }, [navigate, setToken, setRegistrationToken]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-primary">
      <p className="text-gray-400">Signing in...</p>
    </div>
  );
}
```

**Step 2: Verify build**

Run:
```bash
cd client && npm run build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add client/src/platform/auth/AuthCallback.tsx
git commit -m "feat: handle registration_token in AuthCallback"
```

---

## Task 9: Client — RegisterPage Component

**Files:**
- Create: `client/src/platform/auth/RegisterPage.tsx`

**Step 1: Create the registration form**

Create `client/src/platform/auth/RegisterPage.tsx`:

```tsx
import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, Navigate } from 'react-router';
import { useAuthContext } from './AuthProvider.tsx';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';
const NICKNAME_REGEX = /^[a-zA-Z][a-zA-Z0-9_]{2,19}$/;
const DEBOUNCE_MS = 300;

type NicknameStatus = 'idle' | 'checking' | 'available' | 'taken' | 'invalid';

export default function RegisterPage() {
  const navigate = useNavigate();
  const { registrationToken, registrationData, token, setToken, setRegistrationToken } =
    useAuthContext();
  const [displayName, setDisplayName] = useState('');
  const [nickname, setNickname] = useState('');
  const [nicknameStatus, setNicknameStatus] = useState<NicknameStatus>('idle');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (registrationData) {
      setDisplayName(registrationData.name);
    }
  }, [registrationData]);

  const checkNickname = useCallback(async (value: string) => {
    if (!NICKNAME_REGEX.test(value)) {
      setNicknameStatus('invalid');
      return;
    }

    setNicknameStatus('checking');

    const resp = await fetch(
      `${API_URL}/api/auth/check-nickname/${encodeURIComponent(value)}`
    );

    if (resp.ok) {
      const data = (await resp.json()) as { available: boolean };
      setNicknameStatus(data.available ? 'available' : 'taken');
    }
  }, []);

  const handleNicknameChange = useCallback(
    (value: string) => {
      setNickname(value);
      setNicknameStatus('idle');

      if (debounceRef.current) clearTimeout(debounceRef.current);

      if (value.length < 3) {
        setNicknameStatus(value.length > 0 ? 'invalid' : 'idle');
        return;
      }

      debounceRef.current = setTimeout(() => {
        void checkNickname(value);
      }, DEBOUNCE_MS);
    },
    [checkNickname]
  );

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!registrationToken || nicknameStatus !== 'available') return;

      setSubmitting(true);
      setError(null);

      const body: Record<string, string> = {
        registration_token: registrationToken,
        nickname,
        display_name: displayName,
      };

      if (token) {
        body['guest_token'] = token;
      }

      const resp = await fetch(`${API_URL}/api/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      if (resp.ok) {
        const data = (await resp.json()) as { token: string };
        setRegistrationToken(null);
        setToken(data.token);
        navigate('/', { replace: true });
      } else {
        const data = (await resp.json()) as {
          error?: string;
          errors?: Record<string, string[]>;
        };
        setError(
          data.error ?? Object.values(data.errors ?? {}).flat().join(', ') ?? 'Registration failed'
        );
        setSubmitting(false);
      }
    },
    [registrationToken, nickname, displayName, token, nicknameStatus, setToken, setRegistrationToken, navigate]
  );

  if (!registrationToken || !registrationData) {
    return <Navigate to="/login" replace />;
  }

  const canSubmit = nicknameStatus === 'available' && displayName.trim().length > 0 && !submitting;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-8 bg-gradient-to-br from-accent to-cyan bg-clip-text text-4xl font-extrabold uppercase tracking-widest text-transparent">
        Create Account
      </h1>

      <form onSubmit={(e) => void handleSubmit(e)} className="w-full max-w-sm space-y-6">
        <div>
          <label htmlFor="displayName" className="mb-1 block text-sm text-gray-400">
            Full Name
          </label>
          <input
            id="displayName"
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className="w-full rounded-lg border border-border bg-bg-secondary px-4 py-3 text-white focus:border-accent focus:outline-none"
            placeholder="Your full name"
          />
          <p className="mt-1 text-xs text-gray-600">Private — only visible to you</p>
        </div>

        <div>
          <label htmlFor="nickname" className="mb-1 block text-sm text-gray-400">
            Nickname
          </label>
          <input
            id="nickname"
            type="text"
            value={nickname}
            onChange={(e) => handleNicknameChange(e.target.value)}
            className="w-full rounded-lg border border-border bg-bg-secondary px-4 py-3 text-white focus:border-accent focus:outline-none"
            placeholder="Pick a unique handle"
            maxLength={20}
          />
          <div className="mt-1 flex items-center gap-1 text-xs">
            {nicknameStatus === 'idle' && (
              <span className="text-gray-600">3-20 chars, letters/digits/underscores, starts with a letter</span>
            )}
            {nicknameStatus === 'checking' && <span className="text-gray-400">Checking...</span>}
            {nicknameStatus === 'available' && <span className="text-green-400">Available</span>}
            {nicknameStatus === 'taken' && <span className="text-red-400">Already taken</span>}
            {nicknameStatus === 'invalid' && (
              <span className="text-red-400">Must start with a letter, 3-20 chars, letters/digits/underscores</span>
            )}
          </div>
        </div>

        {error && <p className="text-sm text-red-400">{error}</p>}

        <button
          type="submit"
          disabled={!canSubmit}
          className="w-full cursor-pointer rounded-lg bg-accent px-4 py-3 font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {submitting ? 'Creating...' : 'Create Account'}
        </button>
      </form>
    </div>
  );
}
```

**Step 2: Verify build**

Run:
```bash
cd client && npm run build
```

Expected: Build succeeds (component exists but isn't routed yet).

**Step 3: Commit**

```bash
git add client/src/platform/auth/RegisterPage.tsx
git commit -m "feat: add RegisterPage component with nickname availability check"
```

---

## Task 10: Client — App Routing, GameContext, and MainMenu Updates

**Files:**
- Modify: `client/src/App.tsx`
- Modify: `client/src/context/GameContext.tsx`
- Modify: `client/src/components/MainMenu.tsx`
- Modify: `client/src/platform/auth/useAuth.ts`

**Step 1: Add /register route and import to App.tsx**

In `client/src/App.tsx`:

Add import:

```typescript
import RegisterPage from './platform/auth/RegisterPage.tsx';
```

Add route inside `<Routes>`, after the `/oauth/callback` route:

```tsx
<Route path="/register" element={<RegisterPage />} />
```

**Step 2: Update GameContext to use nickname**

Replace line 19 in `client/src/context/GameContext.tsx`:

From:
```typescript
const nickname = user?.displayName ?? null;
```

To:
```typescript
const nickname = user?.nickname ?? user?.displayName ?? null;
```

**Step 3: Update useAuth to expose nickname and isGuest**

Replace `client/src/platform/auth/useAuth.ts`:

```typescript
import { useCallback } from 'react';
import { useAuthContext } from './AuthProvider.tsx';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';

interface UseAuthResult {
  user: { id: string; displayName: string; nickname: string | null } | null;
  token: string | null;
  loading: boolean;
  isAuthenticated: boolean;
  isGuest: boolean;
  loginWithGoogle: () => void;
  loginWithGithub: () => void;
  loginWithDiscord: () => void;
  loginAsGuest: () => Promise<void>;
  logout: () => void;
}

export function useAuth(): UseAuthResult {
  const { user, token, loading, isAuthenticated, setToken, logout } = useAuthContext();

  const isGuest = isAuthenticated && user?.nickname == null;

  const loginWithGoogle = useCallback(() => {
    window.location.href = `${API_URL}/auth/google`;
  }, []);

  const loginWithGithub = useCallback(() => {
    window.location.href = `${API_URL}/auth/github`;
  }, []);

  const loginWithDiscord = useCallback(() => {
    window.location.href = `${API_URL}/auth/discord`;
  }, []);

  const loginAsGuest = useCallback(async () => {
    const resp = await fetch(`${API_URL}/api/auth/guest`, {
      method: 'POST',
    });

    if (resp.ok) {
      const data = (await resp.json()) as { token: string };
      setToken(data.token);
    }
  }, [setToken]);

  return {
    user,
    token,
    loading,
    isAuthenticated,
    isGuest,
    loginWithGoogle,
    loginWithGithub,
    loginWithDiscord,
    loginAsGuest,
    logout,
  };
}
```

**Step 4: Update MainMenu to show nickname and "Link Account" for guests**

Replace `client/src/components/MainMenu.tsx`:

```tsx
import { useNavigate } from 'react-router';
import { useAuth } from '../platform/auth/useAuth.ts';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';

export default function MainMenu() {
  const navigate = useNavigate();
  const { user, isGuest, logout } = useAuth();

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      {user && (
        <div className="absolute top-6 right-6 flex items-center gap-3">
          <span className="text-sm text-gray-400">{user.nickname ?? user.displayName}</span>
          {isGuest && (
            <div className="flex gap-2">
              <a
                href={`${API_URL}/auth/google`}
                className="rounded border border-accent px-3 py-1 text-xs text-accent hover:bg-accent hover:text-white"
              >
                Link Google
              </a>
              <a
                href={`${API_URL}/auth/github`}
                className="rounded border border-accent px-3 py-1 text-xs text-accent hover:bg-accent hover:text-white"
              >
                Link GitHub
              </a>
              <a
                href={`${API_URL}/auth/discord`}
                className="rounded border border-accent px-3 py-1 text-xs text-accent hover:bg-accent hover:text-white"
              >
                Link Discord
              </a>
            </div>
          )}
          <button
            onClick={logout}
            className="cursor-pointer rounded border border-border px-3 py-1 text-xs text-gray-500 hover:text-white"
          >
            Logout
          </button>
        </div>
      )}

      <h1 className="mb-12 bg-gradient-to-br from-accent to-cyan bg-clip-text text-5xl font-extrabold uppercase tracking-widest text-transparent">
        Tetris
      </h1>
      <button
        onClick={() => navigate('/solo')}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-accent px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Solo
      </button>
      <button
        onClick={() => navigate('/lobby')}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-green px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Multiplayer
      </button>
    </div>
  );
}
```

**Step 5: Verify build and lint**

Run:
```bash
cd client && npm run build
cd client && npm run lint
```

Expected: Build and lint pass. Fix any issues.

**Step 6: Commit**

```bash
git add client/src/App.tsx \
  client/src/context/GameContext.tsx \
  client/src/components/MainMenu.tsx \
  client/src/platform/auth/useAuth.ts
git commit -m "feat: add register route, show nickname, add guest upgrade links"
```

---

## Task 11: Full Verification

**Step 1: Run all server tests**

```bash
cd server && mix test
```

Expected: All tests pass.

**Step 2: Run server format and lint**

```bash
cd server && mix format --check-formatted
cd server && mix credo --strict
```

Expected: No issues.

**Step 3: Run client checks**

```bash
cd client && npm run lint
cd client && npm run format:check
cd client && npm run build
```

Expected: All pass.

**Step 4: Manual smoke test**

1. Start PostgreSQL: `docker compose up -d`
2. Reset and start server: `cd server && mix ecto.reset && mix phx.server`
3. Start client: `cd client && npm run dev`
4. Verify:
   - Guest login works (no nickname, shows `Guest_xxx`)
   - Guest can play solo and multiplayer
   - Guest clicks "Link Google/GitHub/Discord" → OAuth flow → registration form appears
   - Registration form pre-fills name, nickname field validates live
   - Submitting registration upgrades guest → JWT refreshed → nickname shows in UI
   - Fresh OAuth login (not guest) → registration form → pick nickname → account created
   - Returning OAuth user → skips registration, goes straight to main menu
   - Nickname shows in lobby, game, and results screens

---

## Infrastructure Prerequisites

Same as auth plan — PostgreSQL running, OAuth provider credentials optional (guest flow tests the full registration pipeline without external providers).
