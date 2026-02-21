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
