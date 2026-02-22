defmodule Platform.History.Match do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "matches" do
    field(:game_type, :string, default: "tetris")
    field(:room_id, :string)
    field(:mode, :string)
    field(:player_count, :integer)
    field(:started_at, :utc_datetime)
    field(:ended_at, :utc_datetime)

    has_many(:match_players, Platform.History.MatchPlayer)

    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [:game_type, :room_id, :mode, :player_count, :started_at, :ended_at])
    |> validate_required([:mode])
    |> validate_inclusion(:mode, ["multiplayer", "solo"])
  end
end
