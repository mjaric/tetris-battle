defmodule TetrisGpt.Training.DataPipeline do
  @moduledoc """
  Transforms recorded game replays into batched structured tensor
  sequences ready for training.

  Pipeline: replay -> per-player sliding windows -> structured
  tensors -> batches

  Each sequence is a tuple {input_map, target, mask} where input_map
  is a map of named tensors matching the model's Axon inputs.
  """

  alias TetrisGpt.Model.Tokenizer

  @doc """
  Convert a replay into a list of {input_map, target, mask} tuples.

  Each tuple represents one sliding window of seq_len timesteps.
  input_map is the structured tensor map from the tokenizer.
  Target is the placement index at each position.
  """
  def replay_to_sequences(replay, opts \\ []) do
    seq_len = Keyword.get(opts, :seq_len, 64)
    min_length = Keyword.get(opts, :min_length, seq_len)

    replay.players
    |> Enum.flat_map(fn {_id, timeline} ->
      if length(timeline) < min_length do
        []
      else
        sliding_windows(timeline, seq_len)
      end
    end)
  end

  @doc """
  Group a list of sequences into batches.

  Returns list of {input_batch_map, target_batch, mask_batch}
  where input_batch_map has each tensor stacked with a batch dim.
  """
  def batch_sequences(sequences, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)

    sequences
    |> Enum.chunk_every(batch_size, batch_size, :discard)
    |> Enum.map(fn batch ->
      {input_maps, targets, masks} = unzip3(batch)

      {
        stack_input_maps(input_maps),
        Nx.stack(targets),
        Nx.stack(masks)
      }
    end)
  end

  @doc "Save sequences to disk as serialized Nx tensors."
  def save(sequences, path) do
    File.mkdir_p!(Path.dirname(path))
    binary = :erlang.term_to_binary(sequences)
    File.write!(path, binary)
  end

  @doc "Load sequences from disk."
  def load(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term()
  end

  defp sliding_windows(timeline, seq_len)
       when length(timeline) < seq_len do
    input_map =
      Tokenizer.encode_structured_sequence(timeline,
        seq_len: seq_len
      )

    targets = extract_targets(timeline, seq_len)
    [{input_map, targets, input_map[:mask]}]
  end

  defp sliding_windows(timeline, seq_len) do
    timeline
    |> Enum.chunk_every(seq_len, 1, :discard)
    |> Enum.filter(fn chunk -> length(chunk) == seq_len end)
    |> Enum.map(fn window ->
      input_map =
        Tokenizer.encode_structured_sequence(window,
          seq_len: seq_len
        )

      targets = extract_targets(window, seq_len)
      {input_map, targets, input_map[:mask]}
    end)
  end

  defp extract_targets(timesteps, seq_len) do
    pad_len = max(0, seq_len - length(timesteps))

    target_indices =
      List.duplicate(0, pad_len) ++
        Enum.map(timesteps, fn ts ->
          Tokenizer.placement_index(
            ts.placement.rotation,
            ts.placement.column
          )
        end)

    target_indices
    |> Enum.take(-seq_len)
    |> Nx.tensor(type: :s32)
  end

  defp stack_input_maps(maps) do
    keys = Map.keys(hd(maps))

    Map.new(keys, fn key ->
      tensors = Enum.map(maps, &Map.fetch!(&1, key))
      {key, Nx.stack(tensors)}
    end)
  end

  defp unzip3(list) do
    {aa, bb, cc} =
      Enum.reduce(list, {[], [], []}, fn {a, b, c}, {as, bs, cs} ->
        {[a | as], [b | bs], [c | cs]}
      end)

    {Enum.reverse(aa), Enum.reverse(bb), Enum.reverse(cc)}
  end
end
