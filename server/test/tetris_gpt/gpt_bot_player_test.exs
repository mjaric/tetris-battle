defmodule TetrisGpt.GptBotPlayerTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.GptBotPlayer

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

  describe "start_link/1" do
    test "starts with waiting phase" do
      room_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        GptBotPlayer.start_link(
          bot_id: "gpt-test-1",
          nickname: "TestGPT",
          room_id: "room-1",
          room_pid: room_pid,
          strategy: TetrisGpt.Strategies.DecoderOnly,
          strategy_opts: [
            checkpoint: nil,
            config: @tiny_config
          ]
        )

      assert Process.alive?(pid)
      Process.exit(pid, :normal)
      Process.exit(room_pid, :normal)
    end
  end
end
