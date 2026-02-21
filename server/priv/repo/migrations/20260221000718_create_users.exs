defmodule Platform.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :text, null: false
      add :provider_id, :text, null: false
      add :email, :text
      add :display_name, :text, null: false
      add :avatar_url, :text
      add :is_anonymous, :boolean, default: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:provider, :provider_id])
    create index(:users, [:display_name])
  end
end
