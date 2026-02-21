defmodule Platform.Accounts do
  @moduledoc false
  import Ecto.Query
  alias Platform.Accounts.User
  alias Platform.Repo

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
