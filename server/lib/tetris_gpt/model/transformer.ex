defmodule TetrisGpt.Model.Transformer do
  @moduledoc """
  Builds the TetrisGPT decoder-only transformer as an Axon model graph.

  Architecture per decoder block:
    LayerNorm -> Multi-Head Attention -> + residual
    LayerNorm -> FFN (d_model -> d_ff -> d_model) -> + residual

  The model accepts multiple named inputs and returns placement
  probabilities of shape {batch, seq_len, num_placements}.
  """

  alias TetrisGpt.Model.Attention

  @doc """
  Build the Axon model graph from config.

  Config keys:
    :d_model, :n_heads, :d_ff, :n_layers, :max_seq_len,
    :num_piece_types, :num_placements, :piece_embed_dim,
    :dropout, :board_dim, :battle_ctx_dim
  """
  def build(config) do
    d_model = config.d_model
    pe = config.piece_embed_dim

    # Inputs (placement is NOT an input — it's the prediction target)
    board = Axon.input("board", shape: {nil, nil, config.board_dim})
    current_piece = Axon.input("current_piece", shape: {nil, nil})
    next_piece = Axon.input("next_piece", shape: {nil, nil})
    battle_ctx = Axon.input("battle_context", shape: {nil, nil, config.battle_ctx_dim})
    _mask = Axon.input("mask", shape: {nil, nil})

    # Embed pieces
    cur_embed =
      Axon.embedding(current_piece, config.num_piece_types, pe, name: "cur_piece_embed")

    nxt_embed =
      Axon.embedding(next_piece, config.num_piece_types, pe, name: "nxt_piece_embed")

    # Project board down to a manageable dimension
    board_proj_dim = max(div(d_model, 2), 8)
    board_proj = Axon.dense(board, board_proj_dim, name: "board_proj")

    # Concatenate all token features then project to d_model
    token =
      Axon.concatenate(
        [board_proj, cur_embed, nxt_embed, battle_ctx],
        axis: 2,
        name: "token_concat"
      )

    token_proj = Axon.dense(token, d_model, name: "token_proj")

    # Add learned positional encoding
    hidden =
      Axon.layer(
        fn x, pos_embed, _opts ->
          seq_len = Nx.axis_size(x, 1)
          pos = Nx.slice_along_axis(pos_embed, 0, seq_len, axis: 0)
          Nx.add(x, pos)
        end,
        [token_proj, Axon.param("pos_embedding", fn _ -> {config.max_seq_len, d_model} end)],
        name: "pos_encoding"
      )

    # Decoder blocks
    hidden =
      Enum.reduce(0..(config.n_layers - 1), hidden, fn i, h ->
        decoder_block(h, config, "block_#{i}")
      end)

    # Final layer norm + output head
    hidden = Axon.layer_norm(hidden, name: "final_norm")

    hidden
    |> Axon.dense(config.num_placements, name: "output_head")
    |> Axon.activation(:softmax, name: "output_softmax")
  end

  defp decoder_block(input, config, prefix) do
    d_model = config.d_model
    n_heads = config.n_heads

    # Sub-layer 1: LayerNorm -> Self-Attention -> Residual
    normed = Axon.layer_norm(input, name: "#{prefix}_norm1")

    attn_out =
      Axon.layer(
        fn x, wq, wk, wv, wo, _opts ->
          seq = Nx.axis_size(x, 1)
          mask = Attention.causal_mask(seq)
          params = %{wq: wq, wk: wk, wv: wv, wo: wo}
          Attention.multi_head(x, x, x, mask, params, n_heads: n_heads)
        end,
        [
          normed,
          Axon.param("#{prefix}_wq", fn _ -> {d_model, d_model} end),
          Axon.param("#{prefix}_wk", fn _ -> {d_model, d_model} end),
          Axon.param("#{prefix}_wv", fn _ -> {d_model, d_model} end),
          Axon.param("#{prefix}_wo", fn _ -> {d_model, d_model} end)
        ],
        name: "#{prefix}_attn"
      )

    after_attn = Axon.add(input, attn_out, name: "#{prefix}_res1")
    after_attn = maybe_dropout(after_attn, config.dropout, "#{prefix}_drop1")

    # Sub-layer 2: LayerNorm -> FFN -> Residual
    normed2 = Axon.layer_norm(after_attn, name: "#{prefix}_norm2")

    ffn_out =
      normed2
      |> Axon.dense(config.d_ff, activation: :gelu, name: "#{prefix}_ffn1")
      |> Axon.dense(d_model, name: "#{prefix}_ffn2")

    after_ffn = Axon.add(after_attn, ffn_out, name: "#{prefix}_res2")
    maybe_dropout(after_ffn, config.dropout, "#{prefix}_drop2")
  end

  defp maybe_dropout(x, rate, name) when rate > 0,
    do: Axon.dropout(x, rate: rate, name: name)

  defp maybe_dropout(x, _rate, _name), do: x

  @doc "Default model config for the tiny (~110K param) model."
  def default_config do
    %{
      d_model: 64,
      n_heads: 4,
      d_ff: 256,
      n_layers: 2,
      max_seq_len: 64,
      num_piece_types: 7,
      num_placements: 40,
      piece_embed_dim: 8,
      dropout: 0.1,
      board_dim: 200,
      battle_ctx_dim: 8
    }
  end
end
