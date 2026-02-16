defmodule TetrisGame.RoomSupervisorTest do
  use ExUnit.Case

  test "starts as a DynamicSupervisor with no children" do
    children = DynamicSupervisor.which_children(TetrisGame.RoomSupervisor)
    assert is_list(children)
    assert length(children) == 0
  end
end
