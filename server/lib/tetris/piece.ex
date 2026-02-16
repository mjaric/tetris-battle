defmodule Tetris.Piece do
  @moduledoc """
  Defines all 7 Tetris tetrominoes with their shapes, colors, and rotation logic.
  """

  @enforce_keys [:type, :shape, :color, :rotation]
  defstruct [:type, :shape, :color, :rotation]

  @type t :: %__MODULE__{
          type: atom(),
          shape: [[integer()]],
          color: String.t(),
          rotation: 0..3
        }

  @tetrominoes %{
    I: %{
      shape: [
        [0, 0, 0, 0],
        [1, 1, 1, 1],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
      color: "#00f0f0"
    },
    O: %{
      shape: [
        [1, 1],
        [1, 1]
      ],
      color: "#f0f000"
    },
    T: %{
      shape: [
        [0, 1, 0],
        [1, 1, 1],
        [0, 0, 0]
      ],
      color: "#a000f0"
    },
    S: %{
      shape: [
        [0, 1, 1],
        [1, 1, 0],
        [0, 0, 0]
      ],
      color: "#00f000"
    },
    Z: %{
      shape: [
        [1, 1, 0],
        [0, 1, 1],
        [0, 0, 0]
      ],
      color: "#f00000"
    },
    J: %{
      shape: [
        [1, 0, 0],
        [1, 1, 1],
        [0, 0, 0]
      ],
      color: "#0000f0"
    },
    L: %{
      shape: [
        [0, 0, 1],
        [1, 1, 1],
        [0, 0, 0]
      ],
      color: "#f0a000"
    }
  }

  @doc """
  Returns a list of all 7 tetromino type atoms.
  """
  @spec types() :: [atom()]
  def types do
    Map.keys(@tetrominoes)
  end

  @doc """
  Creates a new piece from a type atom (e.g., `:T`).
  """
  @spec new(atom()) :: t()
  def new(type) when is_atom(type) do
    definition = Map.fetch!(@tetrominoes, type)

    %__MODULE__{
      type: type,
      shape: definition.shape,
      color: definition.color,
      rotation: 0
    }
  end

  @doc """
  Returns a random piece from the 7 tetrominoes.
  """
  @spec random() :: t()
  def random do
    types()
    |> Enum.random()
    |> new()
  end

  @doc """
  Rotates a piece 90 degrees clockwise.

  For an NxN matrix, the rotation formula is: rotated[i][j] = original[N-1-j][i]
  The rotation field is incremented modulo 4.
  """
  @spec rotate(t()) :: t()
  def rotate(%__MODULE__{shape: shape, rotation: rotation} = piece) do
    rotated_shape = rotate_matrix_clockwise(shape)

    %{piece | shape: rotated_shape, rotation: rem(rotation + 1, 4)}
  end

  defp rotate_matrix_clockwise(matrix) do
    n = length(matrix)

    for i <- 0..(n - 1) do
      for j <- 0..(n - 1) do
        matrix
        |> Enum.at(n - 1 - j)
        |> Enum.at(i)
      end
    end
  end
end
