defmodule Platform.HistoryTest do
  use Platform.DataCase, async: true

  alias Platform.Accounts
  alias Platform.History

  setup do
    {:ok, alice} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "hist_alice",
        display_name: "Alice"
      })

    {:ok, bob} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "hist_bob",
        display_name: "Bob"
      })

    %{alice: alice, bob: bob}
  end

  describe "record_match/1" do
    test "records a multiplayer match with players", %{alice: alice, bob: bob} do
      attrs = %{
        mode: "multiplayer",
        game_type: "tetris",
        room_id: "room_123",
        player_count: 2,
        started_at: DateTime.utc_now() |> DateTime.add(-300) |> DateTime.truncate(:second),
        ended_at: DateTime.utc_now() |> DateTime.truncate(:second),
        players: [
          %{user_id: alice.id, placement: 1, score: 5000, lines_cleared: 20},
          %{user_id: bob.id, placement: 2, score: 3000, lines_cleared: 12}
        ]
      }

      assert {:ok, match} = History.record_match(attrs)
      assert match.mode == "multiplayer"
      assert match.player_count == 2
    end

    test "records a solo match", %{alice: alice} do
      attrs = %{
        mode: "solo",
        player_count: 1,
        players: [
          %{
            user_id: alice.id,
            score: 8000,
            lines_cleared: 40,
            pieces_placed: 120,
            duration_ms: 180_000
          }
        ]
      }

      assert {:ok, match} = History.record_match(attrs)
      assert match.mode == "solo"
    end
  end

  describe "match_exists?/2" do
    test "returns true for existing match" do
      started =
        DateTime.utc_now() |> DateTime.add(-300) |> DateTime.truncate(:second)

      History.record_match(%{
        mode: "multiplayer",
        room_id: "room_dedup",
        started_at: started,
        player_count: 2,
        players: []
      })

      assert History.match_exists?("room_dedup", started)
    end

    test "returns false for non-existing match" do
      refute History.match_exists?("no_such_room", DateTime.utc_now())
    end
  end

  describe "list_matches/2" do
    test "returns matches for a user", %{alice: alice} do
      History.record_match(%{
        mode: "solo",
        player_count: 1,
        players: [%{user_id: alice.id, score: 1000}]
      })

      assert length(History.list_matches(alice.id)) == 1
    end

    test "filters by mode", %{alice: alice} do
      History.record_match(%{
        mode: "solo",
        player_count: 1,
        players: [%{user_id: alice.id, score: 1000}]
      })

      History.record_match(%{
        mode: "multiplayer",
        player_count: 2,
        players: [%{user_id: alice.id, score: 2000}]
      })

      assert length(History.list_matches(alice.id, mode: "solo")) == 1
      assert length(History.list_matches(alice.id, mode: "multiplayer")) == 1
    end

    test "paginates results", %{alice: alice} do
      for i <- 1..5 do
        History.record_match(%{
          mode: "solo",
          player_count: 1,
          players: [%{user_id: alice.id, score: i * 1000}]
        })
      end

      assert length(History.list_matches(alice.id, limit: 2)) == 2
      assert length(History.list_matches(alice.id, limit: 2, offset: 4)) == 1
    end

    test "does not return other users' matches", %{alice: alice, bob: bob} do
      History.record_match(%{
        mode: "solo",
        player_count: 1,
        players: [%{user_id: bob.id, score: 1000}]
      })

      assert History.list_matches(alice.id) == []
    end
  end

  describe "get_match/1" do
    test "returns match with players", %{alice: alice} do
      {:ok, match} =
        History.record_match(%{
          mode: "solo",
          player_count: 1,
          players: [%{user_id: alice.id, score: 5000}]
        })

      assert {:ok, fetched} = History.get_match(match.id)
      assert fetched.id == match.id
      assert length(fetched.match_players) == 1
    end

    test "returns error for missing match" do
      assert {:error, :not_found} = History.get_match(Ecto.UUID.generate())
    end
  end
end
