defmodule TetrisGpt.Model.Tokenizer do
  @moduledoc """
  Converts raw game state into structured tensors for the transformer.

  The tokenizer produces a map of separate tensors — one per input
  type — that map directly to the model's named Axon inputs.
  Dimensionality reduction (board 200→48, piece 7→8, placement
  40→8) happens INSIDE the model via learned Linear/Embedding
  layers, not here.

  Tokenizer output for a sequence of length `seq_len`:

      %{
        "board"          => {seq_len, 200}  float32
        "current_piece"  => {seq_len}       int32
        "next_piece"     => {seq_len}       int32
        "battle_context" => {seq_len, 8}    float32
        "placement"      => {seq_len}       int32
        "mask"           => {seq_len}       float32
      }
  """
  @type piece :: :I | :O | :T | :S | :Z | :J | :L
  @type board :: list(list(String.t()))
  @type rotation :: 0 | 1 | 2 | 3
  @type column :: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
  @type placement_index :: non_neg_integer()
  @type placement :: %{required(:rotation) => rotation(), required(:column) => column()}
  @type battle_context :: %{
          required(:pending_garbage_count) => non_neg_integer(),
          required(:own_max_height) => non_neg_integer(),
          required(:opponent_max_height) => non_neg_integer(),
          required(:combo_count) => non_neg_integer(),
          required(:lines) => non_neg_integer(),
          required(:score_diff) => non_neg_integer(),
          required(:opponent_count) => non_neg_integer(),
          required(:alive) => boolean()
        }
  @type timestep :: %{
          required(:board) => board,
          required(:current_piece) => piece(),
          required(:next_piece) => piece(),
          required(:battle_context) => battle_context(),
          required(:placement) => placement()
        }
  @type structured_tensor_map :: %{
          required(:board) => Nx.Tensor.t(),
          required(:current_piece) => Nx.Tensor.t(),
          required(:next_piece) => Nx.Tensor.t(),
          required(:battle_context) => Nx.Tensor.t(),
          required(:placement) => Nx.Tensor.t(),
          required(:mask) => Nx.Tensor.t()
        }

  # Normalization constants for battle context features.
  # Each value is the practical maximum for that feature,
  # used to scale inputs to roughly [0, 1] for the model.

  # Max garbage rows that can accumulate before a piece locks.
  # 3 opponents × 3 rows each (from 4-line clears) ≈ 9-12.
  @max_pending_garbage 12.0

  # Board height in rows. Column heights range 0-20.
  @board_height 20.0

  # Consecutive line clears beyond 10 are extremely rare.
  @max_combo 10.0

  # Typical battle games end well before 100 total lines.
  @max_lines 100.0

  # Controls tanh sensitivity for unbounded score difference.
  # 1000-point lead → ~0.76, ±3000 saturates near ±1.
  @score_diff_scale 1000.0

  # 4-player game → max 3 opponents.
  @max_opponents 3.0

  @piece_types [:I, :O, :T, :S, :Z, :J, :L]
  @piece_to_index Map.new(Enum.with_index(@piece_types))

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

  @doc "Map piece atom to integer index 0-6."
  @spec piece_index(atom) :: non_neg_integer()
  def piece_index(type) when type in @piece_types do
    Map.fetch!(@piece_to_index, type)
  end

  @doc "Encode placement as single index: rotation * 10 + column."
  @spec placement_index(rotation(), column()) :: non_neg_integer()
  def placement_index(rotation, column)
      when rotation in 0..3 and column in 0..9 do
    rotation * 10 + column
  end

  @doc "Decode placement index back to {rotation, column}."
  @spec decode_placement(index :: placement_index()) :: placement()
  def decode_placement(index) when index in 0..39 do
    %{rotation: div(index, 10), column: rem(index, 10)}
  end

  @doc """
  Encode battle context map to {8} normalized tensor.

  All values scaled to roughly [-1, 1] range:
    0: pending_garbage_count / 12  (max practical garbage queue)
    1: own_max_height / 20         (board height)
    2: opponent_max_height / 20    (board height)
    3: combo_count / 10            (max practical combo)
    4: lines / 100                 (game progress)
    5: tanh(score_diff / 1000)     (relative standing, squashed)
    6: opponent_count / 3          (max opponents in 4-player)
    7: alive (0.0 or 1.0)         (binary flag)
  """
  @spec encode_battle_context(ctx :: TetrisGpt.Strategy.context()) :: Nx.Tensor.t()
  def encode_battle_context(ctx) do
    Nx.tensor(
      [
        (ctx[:pending_garbage_count] || 0) / @max_pending_garbage,
        (ctx[:own_max_height] || 0) / @board_height,
        (ctx[:opponent_max_height] || 0) / @board_height,
        (ctx[:combo_count] || 0) / @max_combo,
        (ctx[:lines] || 0) / @max_lines,
        :math.tanh((ctx[:score_diff] || 0) / @score_diff_scale),
        (ctx[:opponent_count] || 0) / @max_opponents,
        if(ctx[:alive] == false, do: 0.0, else: 1.0)
      ],
      type: :f32
    )
  end

  @doc """
  Encode a list of timesteps into a structured tensor map.

  ## Returns

  Returns a map of named tensors matching the model's Axon inputs:

  ```elixir
    %{
      "board"          => {seq_len, 200},  # float32
      "current_piece"  => {seq_len},       # int32
      "next_piece"     => {seq_len},       # int32
      "battle_context" => {seq_len, 8},    # float32
      "placement"      => {seq_len},       # int32
      "mask"           => {seq_len}        # float32
    }
  ```

  Sequences shorter than `seq_len` are left-padded with zeros.
  Sequences longer than `seq_len` are truncated (keep most recent).

  ## Options

    * `:seq_len` - target sequence length (default: 64)
  """
  @spec encode_structured_sequence([timestep()], keyword()) :: structured_tensor_map()
  def encode_structured_sequence(timesteps, opts \\ []) do
    seq_len = Keyword.get(opts, :seq_len, 64)

    recent = Enum.take(timesteps, -seq_len)
    actual_len = length(recent)
    pad_len = seq_len - actual_len

    boards = Enum.map(recent, fn ts -> encode_board(ts.board) end)

    current_pieces =
      Enum.map(recent, fn ts -> piece_index(ts.current_piece) end)

    next_pieces =
      Enum.map(recent, fn ts -> piece_index(ts.next_piece) end)

    battle_contexts =
      Enum.map(recent, fn ts ->
        encode_battle_context(ts.battle_context)
      end)

    placements =
      Enum.map(recent, fn ts ->
        placement_index(ts.placement.rotation, ts.placement.column)
      end)

    # Build padded tensors
    pad_board = Nx.broadcast(0.0, {200})
    pad_battle = Nx.broadcast(0.0, {8})

    board_tensor =
      (List.duplicate(pad_board, pad_len) ++ boards)
      |> Nx.stack()

    current_piece_tensor =
      (List.duplicate(0, pad_len) ++ current_pieces)
      |> Nx.tensor(type: :s32)

    next_piece_tensor =
      (List.duplicate(0, pad_len) ++ next_pieces)
      |> Nx.tensor(type: :s32)

    battle_context_tensor =
      (List.duplicate(pad_battle, pad_len) ++ battle_contexts)
      |> Nx.stack()

    placement_tensor =
      (List.duplicate(0, pad_len) ++ placements)
      |> Nx.tensor(type: :s32)

    mask_list =
      List.duplicate(0.0, pad_len) ++
        List.duplicate(1.0, actual_len)

    mask_tensor = Nx.tensor(mask_list, type: :f32)

    %{
      board: board_tensor,
      current_piece: current_piece_tensor,
      next_piece: next_piece_tensor,
      battle_context: battle_context_tensor,
      placement: placement_tensor,
      mask: mask_tensor
    }
  end
end
