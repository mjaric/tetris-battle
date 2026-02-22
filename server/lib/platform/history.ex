defmodule Platform.History do
  @moduledoc """
  Context for match history projections in Postgres.
  """

  import Ecto.Query
  alias Platform.History.{Match, MatchPlayer}
  alias Platform.Repo

  def record_match(attrs) do
    Repo.transaction(fn ->
      {:ok, match} =
        %Match{}
        |> Match.changeset(Map.drop(attrs, [:players]))
        |> Repo.insert()

      insert_players(match, attrs[:players] || [])
      match
    end)
  end

  defp insert_players(match, players) do
    Enum.each(players, fn player_attrs ->
      {:ok, _} =
        %MatchPlayer{}
        |> MatchPlayer.changeset(Map.put(player_attrs, :match_id, match.id))
        |> Repo.insert()
    end)
  end

  def match_exists?(room_id, started_at) when is_binary(room_id) do
    from(m in Match,
      where: m.room_id == ^room_id and m.started_at == ^started_at
    )
    |> Repo.exists?()
  end

  def list_matches(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    mode = Keyword.get(opts, :mode)

    query =
      from(m in Match,
        join: mp in MatchPlayer,
        on: mp.match_id == m.id,
        where: mp.user_id == ^user_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:match_players]
      )

    query =
      if mode do
        where(query, [m], m.mode == ^mode)
      else
        query
      end

    Repo.all(query)
  end

  def get_match(match_id) do
    case Repo.get(Match, match_id) do
      nil -> {:error, :not_found}
      match -> {:ok, Repo.preload(match, [:match_players])}
    end
  end
end
