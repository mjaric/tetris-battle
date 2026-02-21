defmodule Platform.Accounts.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field(:provider, :string)
    field(:provider_id, :string)
    field(:email, :string)
    field(:display_name, :string)
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
    :settings
  ]

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:provider, :provider_id])
  end
end
