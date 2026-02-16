defmodule Tetris.WallKicks do
  @moduledoc """
  Super Rotation System (SRS) wall kick data for Tetris pieces.

  When a piece rotation causes a collision, the game attempts a series of
  position offsets (wall kicks) to find a valid placement. This module
  provides the kick offset data for each rotation transition.
  """

  @normal_kicks %{
    {0, 1} => [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}],
    {1, 0} => [{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}],
    {1, 2} => [{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}],
    {2, 1} => [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}],
    {2, 3} => [{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}],
    {3, 2} => [{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}],
    {3, 0} => [{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}],
    {0, 3} => [{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}]
  }

  @i_kicks %{
    {0, 1} => [{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}],
    {1, 0} => [{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}],
    {1, 2} => [{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}],
    {2, 1} => [{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}],
    {2, 3} => [{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}],
    {3, 2} => [{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}],
    {3, 0} => [{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}],
    {0, 3} => [{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}]
  }

  @doc """
  Returns a list of `{dx, dy}` kick offsets for the given piece type and rotation transition.

  ## Parameters

    - `piece_type` - atom representing the piece (`:I`, `:O`, `:T`, `:S`, `:Z`, `:J`, `:L`)
    - `transition` - tuple `{from_rotation, to_rotation}` where rotations are 0..3

  ## Examples

      iex> Tetris.WallKicks.get(:T, {0, 1})
      [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}]

      iex> Tetris.WallKicks.get(:O, {0, 1})
      [{0, 0}]

  """
  @spec get(atom(), {non_neg_integer(), non_neg_integer()}) :: [{integer(), integer()}]
  def get(:I, transition) do
    Map.fetch!(@i_kicks, transition)
  end

  def get(:O, _transition) do
    [{0, 0}]
  end

  def get(_type, transition) do
    Map.fetch!(@normal_kicks, transition)
  end
end
