defmodule TetrisGpt.Training.TrainerTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Model.Transformer
  alias TetrisGpt.Training.Trainer

  @test_config %{
    d_model: 16,
    n_heads: 2,
    d_ff: 32,
    n_layers: 1,
    max_seq_len: 4,
    num_piece_types: 7,
    num_placements: 40,
    piece_embed_dim: 4,
    dropout: 0.0,
    board_dim: 200,
    battle_ctx_dim: 8
  }

  defp make_batch(batch_size, seq_len) do
    key = Nx.Random.key(System.unique_integer([:positive]))
    {board, key} = Nx.Random.normal(key, shape: {batch_size, seq_len, 200})
    {battle_ctx, key} = Nx.Random.normal(key, shape: {batch_size, seq_len, 8})

    {cur_piece, key} =
      Nx.Random.randint(key, 0, 7,
        shape: {batch_size, seq_len},
        type: :s32
      )

    {nxt_piece, key} =
      Nx.Random.randint(key, 0, 7,
        shape: {batch_size, seq_len},
        type: :s32
      )

    {placement, _key} =
      Nx.Random.randint(key, 0, 40,
        shape: {batch_size, seq_len},
        type: :s32
      )

    %{
      "board" => board,
      "current_piece" => cur_piece,
      "next_piece" => nxt_piece,
      "battle_context" => battle_ctx,
      "placement" => placement,
      "mask" => Nx.broadcast(1.0, {batch_size, seq_len})
    }
  end

  describe "train/3" do
    @tag timeout: 120_000
    test "runs one epoch and returns params" do
      model = Transformer.build(@test_config)

      train_data =
        Stream.repeatedly(fn ->
          batch = make_batch(2, 4)

          key =
            Nx.Random.key(System.unique_integer([:positive]))

          {targets, _key} =
            Nx.Random.randint(key, 0, 40,
              shape: {2, 4},
              type: :s32
            )

          {batch, targets}
        end)
        |> Stream.take(2)

      params = Trainer.train(model, train_data, epochs: 1)
      assert is_map(params)
    end
  end
end
