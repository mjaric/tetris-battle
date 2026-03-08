defmodule TetrisGpt.Strategies.DecoderOnly do
  @moduledoc """
  Decoder-only transformer strategy for TetrisGpt.

  Maintains a sliding window of past game states and runs
  the transformer model to predict the best placement.
  """

  @behaviour TetrisGpt.Strategy

  alias Tetris.{BotStrategy, Piece}
  alias TetrisGpt.Model.{Tokenizer, Transformer}
  alias TetrisGpt.Training.Trainer

  @max_history 64

  @impl true
  def name, do: "decoder_only"

  @impl true
  def init(opts) do
    config =
      Keyword.get(opts, :config, Transformer.default_config())

    model = Transformer.build(config)
    {init_fn, predict_fn} = Axon.build(model, mode: :inference)

    params =
      case Keyword.get(opts, :checkpoint) do
        nil ->
          dummy_input = dummy_input(config)
          init_fn.(dummy_input, %{})

        path ->
          Trainer.load_params(path)
      end

    %{
      predict_fn: predict_fn,
      params: params,
      config: config,
      history: []
    }
  end

  @impl true
  def predict(state, context) do
    # Build timestep with placeholder placement
    timestep = %{
      board: context.board,
      current_piece: context.current_piece,
      next_piece: context.next_piece,
      battle_context: context.battle_context,
      placement: %{rotation: 0, column: 0}
    }

    history =
      Enum.take(state.history ++ [timestep], -@max_history)

    # Encode and convert atom keys to string keys for Axon
    input_map =
      history
      |> Tokenizer.encode_structured_sequence(seq_len: state.config.max_seq_len)
      |> to_string_keys()
      |> add_batch_dim()

    # Run inference
    output = state.predict_fn.(state.params, input_map)

    # Get probabilities for the last position
    last_pos = Nx.axis_size(output, 1) - 1
    logits = output[[0, last_pos]]

    # Mask invalid placements
    piece = Piece.new(context.current_piece)
    valid_mask = valid_placement_mask(context.board, piece)
    masked_logits = Nx.add(logits, valid_mask)

    # Select best placement
    best_idx = Nx.argmax(masked_logits) |> Nx.to_number()
    placement = Tokenizer.decode_placement(best_idx)

    # Update history with actual chosen placement
    updated_timestep = %{timestep | placement: placement}
    final_history = List.replace_at(history, -1, updated_timestep)

    {placement, %{state | history: final_history}}
  end

  defp to_string_keys(map) do
    Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp add_batch_dim(map) do
    Map.new(map, fn {k, v} -> {k, Nx.new_axis(v, 0)} end)
  end

  defp valid_placement_mask(board, piece) do
    valid_indices =
      board
      |> BotStrategy.enumerate_placements(piece)
      |> Enum.map(fn pl ->
        Tokenizer.placement_index(
          pl.rotation_count,
          pl.target_x
        )
      end)
      |> MapSet.new()

    Enum.map(0..39, fn i ->
      if MapSet.member?(valid_indices, i), do: 0.0, else: -1.0e9
    end)
    |> Nx.tensor(type: :f32)
  end

  defp dummy_input(config) do
    seq = config.max_seq_len

    %{
      "board" => Nx.broadcast(0.0, {1, seq, config.board_dim}),
      "current_piece" => Nx.broadcast(0, {1, seq}),
      "next_piece" => Nx.broadcast(0, {1, seq}),
      "battle_context" => Nx.broadcast(0.0, {1, seq, config.battle_ctx_dim}),
      "placement" => Nx.broadcast(0, {1, seq}),
      "mask" => Nx.broadcast(1.0, {1, seq})
    }
  end
end
