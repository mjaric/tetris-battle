defmodule Mix.Tasks.TetrisGpt.Record do
  @shortdoc "Record bot-vs-bot battle games for TetrisGpt training"

  @moduledoc """
  Records bot-vs-bot games and saves replay data for training.

  ## Usage

      mix tetris_gpt.record --games 100

  ## Options

    * `--games` - Number of games to record (default: 100)
    * `--difficulty` - Bot difficulty: hard, battle (default: hard)
    * `--output` - Output directory (default: priv/tetris_gpt/data)
  """

  use Mix.Task

  alias TetrisGpt.Training.{DataPipeline, GameRecorder}

  require Logger

  @switches [games: :integer, difficulty: :string, output: :string]
  @aliases [g: :games, d: :difficulty, o: :output]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:exla)

    {opts, _, _} =
      OptionParser.parse(args,
        switches: @switches,
        aliases: @aliases
      )

    num_games = Keyword.get(opts, :games, 100)

    difficulty =
      opts
      |> Keyword.get(:difficulty, "hard")
      |> String.to_existing_atom()

    output_dir =
      Keyword.get(opts, :output, "priv/tetris_gpt/data")

    File.mkdir_p!(output_dir)

    Logger.info("Recording #{num_games} #{difficulty} bot battles...")

    replays =
      Enum.map(1..num_games, fn i ->
        if rem(i, 10) == 0 do
          Logger.info("  Game #{i}/#{num_games}")
        end

        GameRecorder.record_game(difficulty: difficulty)
      end)

    sequences =
      Enum.flat_map(replays, fn replay ->
        DataPipeline.replay_to_sequences(replay, seq_len: 64)
      end)

    Logger.info("Generated #{length(sequences)} training sequences")

    output_path = Path.join(output_dir, "sequences.bin")

    DataPipeline.save(sequences, output_path)

    Logger.info("Saved to #{output_path}")
  end
end
