defmodule TetrisGpt.Model.Attention do
  @moduledoc """
  Multi-head attention with standard and flash attention implementations.

  Standard attention materializes the full NxN score matrix.
  Flash attention computes attention in tiles using online softma,
  avoiding the O(N^2) memory cost.

  Both implementations produce indentical results and share the same
  public interface, selectable via the `:mode` option.
  """

  import Nx.Defn

  @doc """
  Create a causal (lower-triangular) attention mask of shape {n, n}.

  This mask should prevent model to look into the future, forcing it to
  compute only based on the moves from the past. Every timestep can see
  self or steps before, never future.
  """
  def causal_mask(n) do
    rows = Nx.iota({n, n}, axis: 0)
    cols = Nx.iota({n, n}, axis: 1)
    Nx.select(Nx.greater(cols, rows), -1.0e9, 0.0)
  end

  @doc """
  Standard scaled dot-product attention.

  Inputs (all tensors):
    q: {batch, heads, seq, d_k}
    k: {batch, heads, seq, d_k}
    v: {batch, heads, seq, d_k}
    mask: {seq, seq} causal mask

  Returns: {batch, heads, seq, d_k}
  """
  defn std(q, k, v, mask) do
    {_, _, _, d_k} = Nx.shape(q)
    scale = Nx.rsqrt(Nx.as_type(d_k, :f32))

    # Compute attention scores: Q * K^T / sqrt(d_k)
    scores = Nx.dot(q, [3], [0, 1], k, [3], [0, 1]) * scale

    # Apply causal mask (broadcast across batch and heads)
    scores = scores + mask

    # Softmax over key dimension
    weights = Nx.exp(scores - Nx.reduce_max(scores, axes: [-1], keep_axes: true))
    weights = weights / Nx.sum(weights, axes: [-1], keep_axes: true)

    # Weighted sum of values
    Nx.dot(weights, [3], [0, 1], v, [2], [0, 1])
  end

  @doc """
  Flash attention — tiled computation with online softmax.

  Same interface and output as standard_attention/4 but computes
  in blocks to avoid materializing the full NxN score matrix.

  Uses the online softmax trick: tracks running maximum (m) and
  running sum of exponentials (l) to compute exact softmax
  incrementally across blocks.
  """
  defn flash(q, k, v, mask, opts \\ []) do
    opts = keyword!(opts, block_size: 16)
    block_size = opts[:block_size]

    {batch, heads, seq_len, d_k} = Nx.shape(q)
    scale = Nx.rsqrt(Nx.as_type(d_k, :f32))
    n_blocks = div(seq_len, block_size)

    output = Nx.broadcast(Nx.tensor(0.0, type: Nx.type(q)), {batch, heads, seq_len, d_k})
    m = Nx.broadcast(Nx.tensor(-1.0e9, type: Nx.type(q)), {batch, heads, seq_len, 1})
    l = Nx.broadcast(Nx.tensor(0.0, type: Nx.type(q)), {batch, heads, seq_len, 1})

    {output, _m, l, _q, _k, _v, _mask, _scale, _j, _n_blocks} =
      while {output, m, l, q, k, v, mask, scale, j = Nx.tensor(0), n_blocks},
            j < n_blocks do
        j_start = j * block_size

        k_block = Nx.slice_along_axis(k, j_start, block_size, axis: 2)
        v_block = Nx.slice_along_axis(v, j_start, block_size, axis: 2)

        s_block = Nx.dot(q, [3], [0, 1], k_block, [3], [0, 1]) * scale

        mask_block = Nx.slice_along_axis(mask, j_start, block_size, axis: 1)
        s_block = s_block + mask_block

        m_block = Nx.reduce_max(s_block, axes: [-1], keep_axes: true)
        m_new = Nx.max(m, m_block)

        alpha = Nx.exp(m - m_new)
        p_block = Nx.exp(s_block - m_new)
        l_new = alpha * l + Nx.sum(p_block, axes: [-1], keep_axes: true)

        output_new = alpha * output + Nx.dot(p_block, [3], [0, 1], v_block, [2], [0, 1])

        {output_new, m_new, l_new, q, k, v, mask, scale, j + 1, n_blocks}
      end

    output / Nx.max(l, 1.0e-9)
  end

  @doc """
  Initialize random parameters for multi-head attention.

  Returns a map with :wq, :wk, :wv, :wo weight matrices.
  Used for standalone testing; in the full model, Axon manages params.
  """
  def init_mha_params(d_model, n_heads) do
    key = Nx.Random.key(0)
    scale = :math.sqrt(2.0 / d_model)

    {wq, key} = Nx.Random.normal(key, shape: {d_model, d_model})
    {wk, key} = Nx.Random.normal(key, shape: {d_model, d_model})
    {wv, key} = Nx.Random.normal(key, shape: {d_model, d_model})
    {wo, _key} = Nx.Random.normal(key, shape: {d_model, d_model})

    %{
      wq: Nx.multiply(wq, scale),
      wk: Nx.multiply(wk, scale),
      wv: Nx.multiply(wv, scale),
      wo: Nx.multiply(wo, scale),
      n_heads: n_heads
    }
  end

  @doc """
  Multi-head attention: project Q/K/V, split heads, attend, concat, project out.

  q_input, k_input, v_input: {batch, seq, d_model}
  mask: {seq, seq}
  params: %{wq, wk, wv, wo, n_heads}

  Returns: {batch, seq, d_model}
  """
  defn multi_head(q_input, k_input, v_input, mask, params, opts \\ []) do
    opts = keyword!(opts, [:n_heads])
    n_heads = opts[:n_heads]

    {batch, seq, d_model} = Nx.shape(q_input)
    d_k = div(d_model, n_heads)

    # Linear projections
    q = Nx.dot(q_input, [2], params.wq, [0])
    k = Nx.dot(k_input, [2], params.wk, [0])
    v = Nx.dot(v_input, [2], params.wv, [0])

    # Reshape to {batch, seq, n_heads, d_k} then transpose to {batch, n_heads, seq, d_k}
    q = q |> Nx.reshape({batch, seq, n_heads, d_k}) |> Nx.transpose(axes: [0, 2, 1, 3])
    k = k |> Nx.reshape({batch, seq, n_heads, d_k}) |> Nx.transpose(axes: [0, 2, 1, 3])
    v = v |> Nx.reshape({batch, seq, n_heads, d_k}) |> Nx.transpose(axes: [0, 2, 1, 3])

    # Apply attention
    attn_out = std(q, k, v, mask)

    # Concat heads: {batch, n_heads, seq, d_k} → {batch, seq, d_model}
    out =
      attn_out
      |> Nx.transpose(axes: [0, 2, 1, 3])
      |> Nx.reshape({batch, seq, d_model})

    # Output projection
    Nx.dot(out, [2], params.wo, [0])
  end
end
