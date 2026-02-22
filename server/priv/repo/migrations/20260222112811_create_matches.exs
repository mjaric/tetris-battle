defmodule Platform.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_type, :text, null: false, default: "tetris"
      add :room_id, :text
      add :mode, :text, null: false
      add :player_count, :integer
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:matches, [:room_id, :started_at],
      where: "room_id IS NOT NULL",
      name: :matches_room_id_started_at_index
    )

    create table(:match_players, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :match_id, references(:matches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :placement, :integer
      add :score, :integer
      add :lines_cleared, :integer
      add :garbage_sent, :integer
      add :garbage_received, :integer
      add :pieces_placed, :integer
      add :duration_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:match_players, [:match_id])
    create index(:match_players, [:user_id])
  end
end
