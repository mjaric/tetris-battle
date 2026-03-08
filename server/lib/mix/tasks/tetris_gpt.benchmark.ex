defmodule Mix.Tasks.TetrisGpt.Benchmark do
  @shortdoc "Benchmark TetrisGpt against heuristic bots"

  @moduledoc """
  Runs TetrisGpt against heuristic bots and reports win rates.

  ## Usage

      mix tetris_gpt.benchmark --checkpoint priv/tetris_gpt/checkpoints/final_params.nx

  ## Options

    * `--games` - Number of benchmark games (default: 20)
    * `--checkpoint` - Model checkpoint path (required)
    * `--opponents` - Opponent difficulty: easy, medium, hard
      (default: easy)
  """

  use Mix.Task

  alias TetrisGpt.Training.Trainer

  require Logger

  @switches [
    games: :integer,
    checkpoint: :string,
    opponents: :string
  ]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:exla)

    {opts, _, _} =
      OptionParser.parse(args, switches: @switches)

    num_games = Keyword.get(opts, :games, 20)
    checkpoint = Keyword.fetch!(opts, :checkpoint)

    opponents =
      opts
      |> Keyword.get(:opponents, "easy")
      |> String.to_existing_atom()

    Logger.info("Loading model from #{checkpoint}...")
    _params = Trainer.load_params(checkpoint)

    Logger.info(
      "Benchmarking TetrisGpt vs #{opponents} bots " <>
        "(#{num_games} games)..."
    )

    Logger.info(
      "Model loaded. Battle simulation not yet implemented " <>
        "- model checkpoint is valid."
    )
  end
end
