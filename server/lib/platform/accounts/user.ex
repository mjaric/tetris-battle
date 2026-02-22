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
    |> validate_required([
      :provider,
      :provider_id,
      :display_name,
      :nickname
    ])
    |> unique_constraint([:provider, :provider_id])
    |> validate_nickname()
  end

  defp validate_nickname(changeset) do
    changeset
    |> validate_format(:nickname, @nickname_format,
      message:
        "must start with a letter, 3-20 chars, " <>
          "letters/digits/underscores only"
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
