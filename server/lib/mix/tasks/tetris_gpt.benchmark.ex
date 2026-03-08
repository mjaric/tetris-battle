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
    Mix.Task.run("compile")

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

    # TODO: Implement battle simulation with TetrisGpt as
    # player 0 and heuristic bots as opponents.
    Logger.info(
      "Benchmark implementation pending " <>
        "- model loads successfully"
    )
  end
end
