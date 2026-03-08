defmodule TetrisGpt.Strategies.DecoderOnlyTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Strategies.DecoderOnly

  @tiny_config %{
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

  describe "behaviour compliance" do
    test "name returns string" do
      assert DecoderOnly.name() == "decoder_only"
    end

    test "init returns state with model params" do
      state = DecoderOnly.init(checkpoint: nil, config: @tiny_config)
      assert is_map(state)
      assert state.history == []
    end

    test "predict returns valid placement" do
      state = DecoderOnly.init(checkpoint: nil, config: @tiny_config)

      context = %{
        board: List.duplicate(List.duplicate(nil, 10), 20),
        current_piece: :T,
        next_piece: :I,
        battle_context: %{
          pending_garbage_count: 0,
          own_max_height: 0,
          opponent_max_height: 0,
          combo_count: 0,
          lines: 0,
          score_diff: 0,
          opponent_count: 3,
          alive: true
        }
      }

      {placement, new_state} = DecoderOnly.predict(state, context)
      assert placement.rotation in 0..3
      assert placement.column in 0..9
      assert length(new_state.history) == 1
    end
  end
end
