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

  alias TetrisGpt.Strategies.DecoderOnly
  alias TetrisGpt.Training.BenchmarkSimulation

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
      |> String.to_atom()

    Logger.info("Loading model from #{checkpoint}...")
    strategy_state = DecoderOnly.init(checkpoint: checkpoint)

    Logger.info(
      "Benchmarking TetrisGpt vs #{opponents} bots " <>
        "(#{num_games} games)..."
    )

    summary =
      BenchmarkSimulation.run_benchmark(
        DecoderOnly,
        strategy_state,
        num_games: num_games,
        difficulty: opponents
      )

    report_results(summary, opponents)
  end

  defp report_results(summary, opponents) do
    Logger.info("")
    Logger.info("=== Benchmark Results ===")

    Logger.info("Games: #{summary.games} | Opponents: #{opponents}")

    win_pct = Float.round(summary.win_rate * 100, 1)

    Logger.info(
      "GPT wins: #{summary.gpt_wins}/#{summary.games} " <>
        "(#{win_pct}%)"
    )

    Logger.info("Avg GPT lines: #{Float.round(summary.avg_gpt_lines, 1)}")

    Logger.info("Avg GPT pieces: #{Float.round(summary.avg_gpt_pieces, 1)}")

    Logger.info("")

    Enum.each(summary.results, fn r ->
      result = if r.gpt_won, do: "WIN", else: "LOSS"
      gpt = r.stats[0]

      Logger.info(
        "  Game #{r.game_num}: #{result} | " <>
          "lines=#{gpt.lines} pieces=#{gpt.pieces_placed}"
      )
    end)
  end
end
