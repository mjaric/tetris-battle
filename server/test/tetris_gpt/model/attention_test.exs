defmodule TetrisGpt.Model.AttentionTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Model.Attention

  describe "causal_mask/1" do
    test "creates lower-triangular mask" do
      mask = Attention.causal_mask(4)
      assert Nx.shape(mask) == {4, 4}

      expected =
        Nx.tensor([
          [0.0, -1.0e9, -1.0e9, -1.0e9],
          [0.0, 0.0, -1.0e9, -1.0e9],
          [0.0, 0.0, 0.0, -1.0e9],
          [0.0, 0.0, 0.0, 0.0]
        ])

      assert Nx.all_close(mask, expected, atol: 1.0) == Nx.tensor(1, type: :u8)
    end
  end

  describe "standard attention/4" do
    test "output shape matches input" do
      key = Nx.Random.key(0)
      {q, key} = Nx.Random.normal(key, shape: {2, 4, 8, 16})
      {k, key} = Nx.Random.normal(key, shape: {2, 4, 8, 16})
      {v, _key} = Nx.Random.normal(key, shape: {2, 4, 8, 16})
      mask = Attention.causal_mask(8)

      output = Attention.std(q, k, v, mask)
      assert Nx.shape(output) == {2, 4, 8, 16}
    end

    test "respect causal mask - first position only attends to itself" do
      q = Nx.tensor([[[[1.0, 0.0], [0.0, 1.0]]]])
      k = Nx.tensor([[[[1.0, 0.0], [0.0, 1.0]]]])
      v = Nx.tensor([[[[1.0, 20.0], [30.0, 40.0]]]])
      mask = Attention.causal_mask(2)

      output = Attention.std(q, k, v, mask)
      pos0 = output[[0, 0, 0]]
      assert Nx.all_close(pos0, Nx.tensor([1.0, 20.0]), atol: 0.01) == Nx.tensor(1, type: :u8)
    end
  end

  describe "flash/4" do
    test "output shape matches input" do
      key = Nx.Random.key(1)
      {q, key} = Nx.Random.normal(key, shape: {2, 4, 8, 16})
      {k, key} = Nx.Random.normal(key, shape: {2, 4, 8, 16})
      {v, _key} = Nx.Random.normal(key, shape: {2, 4, 8, 16})
      mask = Attention.causal_mask(8)

      output = Attention.flash(q, k, v, mask, block_size: 8)
      assert Nx.shape(output) == {2, 4, 8, 16}
    end

    test "matches standard attention output" do
      key = Nx.Random.key(42)
      {q, key} = Nx.Random.normal(key, shape: {1, 4, 16, 16})
      {k, key} = Nx.Random.normal(key, shape: {1, 4, 16, 16})
      {v, _key} = Nx.Random.normal(key, shape: {1, 4, 16, 16})
      mask = Attention.causal_mask(16)

      standard = Attention.std(q, k, v, mask)
      flash = Attention.flash(q, k, v, mask, block_size: 4)

      assert Nx.all_close(standard, flash, atol: 1.0e-4) ==
               Nx.tensor(1, type: :u8)
    end
  end

  describe "multi_head_attention/5" do
    test "projects input and applies attention" do
      # batch=1, seq=8, d_model=64
      key = Nx.Random.key(2)
      {input, _key} = Nx.Random.normal(key, shape: {1, 8, 64})
      mask = Attention.causal_mask(8)

      params = Attention.init_mha_params(64, 4)

      output =
        Attention.multi_head(input, input, input, mask, params, n_heads: 4)

      assert Nx.shape(output) == {1, 8, 64}
    end
  end
end
