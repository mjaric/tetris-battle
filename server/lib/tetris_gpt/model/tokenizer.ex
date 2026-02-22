defmodule TetrisGpt.Model.Tokenizer do
  @moduledoc """
  Converts raw game state into tensors for the transformer model.

  Each game timestep becomes an 80-element float32 vector:
    - Board: 20x10 binary grid, flattened (200 → kept as 200 in raw form)
    - Current piece: integer index 0-6
    - Next piece: integer index 0-6
    - Battle context: 8 normalized floats
    - Placement action: integer index 0-39

  The raw 80-feature vector is composed as:
    [board(200) | current_piece(1) | next_piece(1) |
     battle_context(8) | placement(1)]
  totaling 210 raw features. However, piece and placement indices
  are stored separately for embedding lookup. The 80-feature
  "token" is assembled after embedding projection inside the model.

  For the tokenizer output consumed by the model input pipeline:
    - board_flat: {seq_len, 200} float32
    - current_piece: {seq_len} int32
    - next_piece: {seq_len} int32
    - battle_context: {seq_len, 8} float32
    - placement: {seq_len} int32
    - mask: {seq_len} float32
  """

  @type board :: list(list(String.t()))

  @doc "Number of distinct piece types."
  @spec num_piece_types() :: non_neg_integer()
  def num_piece_types, do: 7

  @doc "Number of distinct placements (4 rotations and 10 columns)."
  @spec num_placements() :: non_neg_integer()
  def num_placements, do: 40

  @doc """
  Convert a 20x10 board to a `{200}` `f32` binary tensor.

  This is list of lists, and first is number of rows (20),
  then 10 columns in each row.
  """
  @spec encode_board(board()) :: Nx.Tensor.t()
  def encode_board(board) do
    board
    |> List.flatten()
    |> Enum.map(fn cell -> if cell == nil, do: 0.0, else: 1.0 end)
    |> Nx.tensor(type: :f32)
  end
end
