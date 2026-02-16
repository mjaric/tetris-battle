defmodule TetrisGame.BotNames do
  @moduledoc """
  Predefined funny names for bot players.
  """

  @names [
    "StackOverlord",
    "T-SpinTerror",
    "GarbageMaster",
    "BlockDropper3000",
    "TetrominoTim",
    "ClearLineCarla",
    "WallKickWizard",
    "GravityGremlin",
    "PiecePlacerPete",
    "ComboKing",
    "RowReaper",
    "DropZoneDave",
    "TetrisToaster",
    "PixelPusher",
    "GridGoblin",
    "NeonNinja",
    "ByteBlocker",
    "StackAttack",
    "LineClearLarry",
    "RoboTetromino"
  ]

  @doc """
  Picks a random name not in the exclusion list.

  Falls back to "Bot-{random}" if all names are taken.
  """
  @spec pick([String.t()]) :: String.t()
  def pick(excluded_names \\ []) do
    available = @names -- excluded_names

    if available == [] do
      "Bot-#{:rand.uniform(9999)}"
    else
      Enum.random(available)
    end
  end

  @doc """
  Returns the full list of bot names.
  """
  @spec all() :: [String.t()]
  def all, do: @names
end
