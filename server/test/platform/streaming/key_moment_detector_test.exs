defmodule Platform.Streaming.KeyMomentDetectorTest do
  use ExUnit.Case, async: true

  alias Platform.Streaming.KeyMomentDetector

  setup do
    %{state: KeyMomentDetector.new_game_state()}
  end

  describe "tetris detection" do
    test "detects 4-line clear as tetris", %{state: state} do
      event = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 100,
        "count" => 4
      }

      {moments, _state} = KeyMomentDetector.detect_moments(event, state)
      assert [%{type: "tetris", player_id: "p1"}] = moments
    end

    test "does not detect 1-3 line clears", %{state: state} do
      for count <- [1, 2, 3] do
        event = %{
          "type" => "line_clear",
          "player_id" => "p1",
          "tick" => 100,
          "count" => count
        }

        {moments, _} = KeyMomentDetector.detect_moments(event, state)
        assert moments == []
      end
    end
  end

  describe "back_to_back detection" do
    test "detects consecutive tetris as back_to_back", %{state: state} do
      e1 = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 100,
        "count" => 4
      }

      {_, state} = KeyMomentDetector.detect_moments(e1, state)

      e2 = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 200,
        "count" => 4
      }

      {moments, _} = KeyMomentDetector.detect_moments(e2, state)
      types = Enum.map(moments, & &1.type)
      assert "back_to_back" in types
    end

    test "non-tetris clear breaks chain", %{state: state} do
      e1 = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 100,
        "count" => 4
      }

      {_, state} = KeyMomentDetector.detect_moments(e1, state)

      e2 = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 150,
        "count" => 2
      }

      {_, state} = KeyMomentDetector.detect_moments(e2, state)

      e3 = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 200,
        "count" => 4
      }

      {moments, _} = KeyMomentDetector.detect_moments(e3, state)
      types = Enum.map(moments, & &1.type)
      refute "back_to_back" in types
    end
  end

  describe "garbage_surge detection" do
    test "detects 3+ consecutive garbage_sent", %{state: state} do
      events =
        for i <- 1..3 do
          %{
            "type" => "garbage_sent",
            "player_id" => "p1",
            "tick" => i * 10,
            "count" => 2
          }
        end

      {_moments, state} =
        KeyMomentDetector.detect_moments(Enum.at(events, 0), state)

      {_moments, state} =
        KeyMomentDetector.detect_moments(Enum.at(events, 1), state)

      {moments, _state} =
        KeyMomentDetector.detect_moments(Enum.at(events, 2), state)

      assert [%{type: "garbage_surge", streak: 3}] = moments
    end

    test "non-garbage event resets streak", %{state: state} do
      e1 = %{
        "type" => "garbage_sent",
        "player_id" => "p1",
        "tick" => 10,
        "count" => 2
      }

      {_, state} = KeyMomentDetector.detect_moments(e1, state)

      e2 = %{
        "type" => "line_clear",
        "player_id" => "p1",
        "tick" => 20,
        "count" => 1
      }

      {_, state} = KeyMomentDetector.detect_moments(e2, state)

      e3 = %{
        "type" => "garbage_sent",
        "player_id" => "p1",
        "tick" => 30,
        "count" => 2
      }

      {moments, _} = KeyMomentDetector.detect_moments(e3, state)
      assert moments == []
    end
  end

  describe "elimination detection" do
    test "detects elimination event", %{state: state} do
      event = %{"type" => "elimination", "player_id" => "p2", "tick" => 500}

      {moments, _} = KeyMomentDetector.detect_moments(event, state)
      assert [%{type: "elimination", player_id: "p2"}] = moments
    end
  end

  describe "game_end cleanup" do
    test "returns :cleanup signal", %{state: state} do
      event = %{"type" => "game_end", "tick" => 1000}
      {moments, new_state} = KeyMomentDetector.detect_moments(event, state)

      assert moments == []
      assert new_state == :cleanup
    end
  end
end
