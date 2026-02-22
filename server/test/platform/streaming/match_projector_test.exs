defmodule Platform.Streaming.MatchProjectorTest do
  use Platform.DataCase, async: true

  alias Platform.History
  alias Platform.Streaming.MatchProjector

  @game_end_event %{
    "type" => "game_end",
    "tick" => 1000,
    "data" => %{
      "room_id" => "room_proj_test",
      "mode" => "multiplayer",
      "player_count" => 2,
      "eliminated_order" => ["p2"],
      "started_at" => "2026-02-20T10:00:00Z",
      "ended_at" => "2026-02-20T10:05:00Z",
      "players" => [
        %{
          "player_id" => "p1",
          "user_id" => nil,
          "placement" => 1,
          "score" => 5000,
          "lines_cleared" => 20,
          "garbage_sent" => 8,
          "garbage_received" => 3,
          "pieces_placed" => 80,
          "duration_ms" => 300_000
        },
        %{
          "player_id" => "p2",
          "user_id" => nil,
          "placement" => 2,
          "score" => 3000,
          "lines_cleared" => 12,
          "garbage_sent" => 3,
          "garbage_received" => 8,
          "pieces_placed" => 60,
          "duration_ms" => 300_000
        }
      ]
    }
  }

  test "project_game_end creates match and players" do
    assert :ok = MatchProjector.project_game_end(@game_end_event)

    match = Repo.one(History.Match)
    assert match.room_id == "room_proj_test"
    assert match.mode == "multiplayer"
    assert match.player_count == 2

    players = Repo.all(History.MatchPlayer)
    assert length(players) == 2
  end

  test "project_game_end is idempotent" do
    assert :ok = MatchProjector.project_game_end(@game_end_event)
    assert :ok = MatchProjector.project_game_end(@game_end_event)

    assert Repo.aggregate(History.Match, :count) == 1
  end

  test "ignores non-game_end events" do
    assert :ok =
             MatchProjector.project_game_end(%{
               "type" => "line_clear",
               "data" => %{}
             })

    assert Repo.aggregate(History.Match, :count) == 0
  end
end
