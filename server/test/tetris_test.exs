defmodule TetrisTest do
  use ExUnit.Case

  test "application starts successfully" do
    assert Process.whereis(Tetris.Supervisor) != nil
  end
end
