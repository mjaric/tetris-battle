defmodule TetrisGame.RoomSupervisor do
  @moduledoc """
  DynamicSupervisor that spawns and supervises GameRoom processes.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_room(room_id, opts) do
    spec = {TetrisGame.GameRoom, [{:room_id, room_id} | opts]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
