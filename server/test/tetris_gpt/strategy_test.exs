defmodule TetrisGpt.StrategyTest do
  use ExUnit.Case, async: true

  defmodule MockStrategy do
    @behaviour TetrisGpt.Strategy

    @impl true
    def name, do: "mock"

    @impl true
    def init(_), do: %{call_count: 0}

    @impl true
    def predict(state, _context) do
      placement = %{rotation: 0, column: 5}
      {placement, %{state | call_count: state.call_count + 1}}
    end
  end

  describe "behaviour compliance" do
    test "mock strategy implement all callbacks" do
      state = MockStrategy.init([])
      assert MockStrategy.name() == "mock"

      context = %{
        board: Nx.broadcast(0, {20, 10}),
        current_piece: :T,
        next_piece: :I,
        battle_context: %{},
        history: []
      }

      {placement, new_state} = MockStrategy.predict(state, context)
      assert placement.rotation in 0..3
      assert placement.column in 0..9
      assert new_state.call_count == 1
    end
  end
end
