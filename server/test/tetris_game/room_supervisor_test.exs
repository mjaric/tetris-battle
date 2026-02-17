defmodule TetrisGame.RoomSupervisorTest do
  use ExUnit.Case

  test "starts as a DynamicSupervisor with no children" do
    # Terminate any children left over from other tests
    for {_, pid, _, _} <- DynamicSupervisor.which_children(TetrisGame.RoomSupervisor),
        is_pid(pid) do
      DynamicSupervisor.terminate_child(TetrisGame.RoomSupervisor, pid)
    end

    children = DynamicSupervisor.which_children(TetrisGame.RoomSupervisor)
    assert is_list(children)
    assert length(children) == 0
  end
end
