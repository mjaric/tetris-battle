defmodule TetrisGpt.Model.TransformerTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Model.Transformer

  @default_config %{
    d_model: 32,
    n_heads: 2,
    d_ff: 128,
    n_layers: 2,
    max_seq_len: 8,
    num_piece_types: 7,
    num_placements: 40,
    piece_embed_dim: 8,
    dropout: 0.0,
    board_dim: 200,
    battle_ctx_dim: 8
  }

  describe "build/1" do
    test "returns an Axon model" do
      model = Transformer.build(@default_config)
      assert %Axon{} = model
    end
  end

  describe "init + predict" do
    test "produces correct output shape" do
      model = Transformer.build(@default_config)

      key = Nx.Random.key(0)
      {board, key} = Nx.Random.normal(key, shape: {1, 8, 200})
      {battle_ctx, _key} = Nx.Random.normal(key, shape: {1, 8, 8})

      input = %{
        "board" => board,
        "current_piece" => Nx.tensor([[0, 1, 2, 3, 4, 5, 6, 0]]),
        "next_piece" => Nx.tensor([[1, 2, 3, 4, 5, 6, 0, 1]]),
        "battle_context" => battle_ctx,
        "mask" => Nx.tensor([[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]])
      }

      {init_fn, predict_fn} = Axon.build(model)
      params = init_fn.(input, Axon.ModelState.empty())
      output = predict_fn.(params, input)

      # Output should be {batch, seq_len, num_placements}
      assert Nx.shape(output) == {1, 8, 40}
    end

    test "output sums to ~1.0 per position after softmax" do
      model = Transformer.build(@default_config)

      key = Nx.Random.key(1)
      {board, key} = Nx.Random.normal(key, shape: {1, 8, 200})
      {battle_ctx, _key} = Nx.Random.normal(key, shape: {1, 8, 8})

      input = %{
        "board" => board,
        "current_piece" => Nx.tensor([[0, 1, 2, 3, 4, 5, 6, 0]]),
        "next_piece" => Nx.tensor([[1, 2, 3, 4, 5, 6, 0, 1]]),
        "battle_context" => battle_ctx,
        "mask" => Nx.tensor([[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]])
      }

      {init_fn, predict_fn} = Axon.build(model)
      params = init_fn.(input, Axon.ModelState.empty())
      output = predict_fn.(params, input)

      # Each position's output should sum to ~1.0 (softmax)
      sums = Nx.sum(output, axes: [2])

      assert Nx.all_close(sums, Nx.broadcast(1.0, {1, 8}), atol: 0.01) ==
               Nx.tensor(1, type: :u8)
    end
  end
end
