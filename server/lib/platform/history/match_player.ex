defmodule Platform.History.MatchPlayer do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_players" do
    belongs_to(:match, Platform.History.Match)
    belongs_to(:user, Platform.Accounts.User)

    field(:placement, :integer)
    field(:score, :integer)
    field(:lines_cleared, :integer)
    field(:garbage_sent, :integer)
    field(:garbage_received, :integer)
    field(:pieces_placed, :integer)
    field(:duration_ms, :integer)

    timestamps(type: :utc_datetime)
  end

  def changeset(mp, attrs) do
    mp
    |> cast(attrs, [
      :match_id,
      :user_id,
      :placement,
      :score,
      :lines_cleared,
      :garbage_sent,
      :garbage_received,
      :pieces_placed,
      :duration_ms
    ])
    |> validate_required([:match_id])
  end
end
