defmodule Platform.Accounts do
  @moduledoc false
  import Ecto.Query
  alias Platform.Accounts.User
  alias Platform.Repo

  @nickname_format ~r/^[a-zA-Z][a-zA-Z0-9_]{2,19}$/

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_provider(provider, provider_id) do
    Repo.get_by(User,
      provider: provider,
      provider_id: provider_id
    )
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

  def register_guest_upgrade(
        %User{is_anonymous: false},
        _attrs
      ) do
    {:error, :not_anonymous}
  end

  def nickname_available?(nickname) do
    Regex.match?(@nickname_format, nickname) and
      not Repo.exists?(from(u in User, where: u.nickname == ^nickname))
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
