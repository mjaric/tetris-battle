defmodule Mix.Tasks.Bot.Evolve.Battle do
  @shortdoc "Evolve battle-aware bot weights via genetic algorithm"
  @moduledoc """
  Runs a genetic algorithm to evolve optimal heuristic weights
  for the Tetris bot's Battle difficulty.

  Uses 4-player battle simulation instead of solo games.
  Starts with static solo opponents, switches to co-evolution
  on stagnation, and falls back if regression is detected.

  ## Usage

      mix bot.evolve.battle [options]

  ## Options

    * `--population N` — Population size (default: 50)
    * `--generations N` — Number of generations (default: 100)
    * `--battles N` — Battles per genome per generation (default: 10)
    * `--concurrency N` — Max parallel evaluations (default: schedulers)
    * `--output PATH` — Output JSON file (default: priv/battle_weights.json)
    * `--log PATH` — CSV log file (default: priv/battle_evolution_log.csv)
    * `--tournament N` — Tournament size (default: 3)
    * `--mutation-rate F` — Mutation probability per weight (default: 0.3)
    * `--mutation-sigma F` — Gaussian std dev (default: 0.15)
    * `--crossover-rate F` — Crossover probability (default: 0.7)
    * `--elitism N` — Elites carried forward (default: 2)
    * `--immigrants N` — Random genomes injected per generation (default: 5)
    * `--stagnation N` — Generations before switching to co-evolution (default: 5)
    * `--regression N` — Generations of decline before reverting (default: 3)
    * `--workers NODES` — Comma-separated worker node names
    * `--cookie COOKIE` — Erlang distribution cookie (default: tetris_evo)

  ## Distributed mode

      mix bot.evolve.battle --workers worker@192.168.1.50 --cookie tetris_evo
  """

  use Mix.Task

  alias BotTrainer.{Cluster, Evolution}

  require Logger

  @switches [
    population: :integer,
    generations: :integer,
    battles: :integer,
    concurrency: :integer,
    output: :string,
    log: :string,
    tournament: :integer,
    mutation_rate: :float,
    mutation_sigma: :float,
    crossover_rate: :float,
    elitism: :integer,
    immigrants: :integer,
    stagnation: :integer,
    regression: :integer,
    workers: :string,
    cookie: :string
  ]

  @aliases [
    p: :population,
    g: :generations,
    n: :battles,
    c: :concurrency,
    o: :output,
    w: :workers
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    setup_cluster(opts)

    nodes = Cluster.available_nodes()
    config = build_config(opts, nodes)
    priv_dir = :code.priv_dir(:tetris) |> to_string()
    output_path = opts[:output] || Path.join(priv_dir, "battle_weights.json")
    log_path = opts[:log] || Path.join(priv_dir, "battle_evolution_log.csv")

    total_battles = config.population_size * config.battles_per_genome * config.generations
    print_header(config, total_battles, nodes)
    init_csv(log_path)

    {best, all_stats} = run_evolution(config, log_path)

    best_fitness = extract_best_fitness(all_stats)
    save_json(output_path, best, best_fitness, config)
    print_chart(all_stats)
    print_summary(best, best_fitness, output_path, log_path)
  end

  defp build_config(opts, nodes) do
    defaults = Evolution.default_battle_config()
    default_concurrency = defaults.max_concurrency * length(nodes)
    base = merge_defaults(opts, defaults)
    Map.put(base, :max_concurrency, opts[:concurrency] || default_concurrency)
  end

  defp merge_defaults(opts, defaults) do
    %{
      population_size: Keyword.get(opts, :population, defaults.population_size),
      generations: Keyword.get(opts, :generations, defaults.generations),
      battles_per_genome: Keyword.get(opts, :battles, defaults.battles_per_genome),
      num_opponents: 3,
      tournament_size: Keyword.get(opts, :tournament, defaults.tournament_size),
      crossover_rate: Keyword.get(opts, :crossover_rate, defaults.crossover_rate),
      mutation_rate: Keyword.get(opts, :mutation_rate, defaults.mutation_rate),
      mutation_sigma: Keyword.get(opts, :mutation_sigma, defaults.mutation_sigma),
      elitism_count: Keyword.get(opts, :elitism, defaults.elitism_count),
      immigrant_count: Keyword.get(opts, :immigrants, defaults.immigrant_count),
      stagnation_threshold: Keyword.get(opts, :stagnation, defaults.stagnation_threshold),
      regression_threshold: Keyword.get(opts, :regression, defaults.regression_threshold),
      lookahead: true
    }
  end

  defp run_evolution(config, log_path) do
    history = :ets.new(:battle_evolution_history, [:ordered_set, :public])

    best =
      Evolution.evolve_battle(config, fn stats ->
        print_generation(stats)
        append_csv(log_path, stats)
        :ets.insert(history, {stats.generation, stats})
      end)

    all_stats = history |> :ets.tab2list() |> Enum.map(fn {_, s} -> s end)
    :ets.delete(history)
    {best, all_stats}
  end

  defp extract_best_fitness([]), do: 0.0

  defp extract_best_fitness(stats) do
    Enum.max_by(stats, & &1.best_fitness).best_fitness
  end

  defp setup_cluster(opts) do
    case opts[:workers] do
      nil ->
        :ok

      workers_str ->
        cookie =
          opts[:cookie]
          |> Kernel.||("tetris_evo")
          |> String.to_atom()

        hostname = local_hostname()
        node_name = :"orchestrator@#{hostname}"

        case Cluster.ensure_distribution(node_name, cookie) do
          :ok ->
            Mix.shell().info("Distribution started as #{node_name}")

          {:error, reason} ->
            Mix.raise("Failed to start distribution: #{inspect(reason)}")
        end

        worker_nodes =
          workers_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.to_atom/1)

        {connected, failed} = Cluster.connect_workers(worker_nodes)

        if connected != [] do
          Mix.shell().info(
            "Connected to #{length(connected)} worker(s): " <>
              Enum.map_join(connected, ", ", &to_string/1)
          )
        end

        if failed != [] do
          Mix.shell().info(
            "Failed to connect: " <>
              Enum.map_join(failed, ", ", &to_string/1)
          )
        end
    end
  end

  defp local_hostname do
    case local_lan_ip() do
      {:ok, ip} -> ip
      :error -> "127.0.0.1"
    end
  end

  defp local_lan_ip do
    with {:ok, ifaddrs} <- :inet.getifaddrs() do
      ifaddrs
      |> Enum.flat_map(&ipv4_addrs_from_iface/1)
      |> List.first()
      |> case do
        nil -> :error
        ip -> {:ok, ip |> :inet.ntoa() |> to_string()}
      end
    end
  end

  defp ipv4_addrs_from_iface({_name, opts}) do
    flags = Keyword.get(opts, :flags, [])

    if :up in flags and :running in flags and :loopback not in flags do
      opts |> Keyword.get_values(:addr) |> Enum.filter(&(tuple_size(&1) == 4))
    else
      []
    end
  end

  defp print_header(config, total_battles, nodes) do
    node_info =
      if length(nodes) > 1 do
        "Nodes:          #{length(nodes)} (#{Enum.map_join(nodes, ", ", &to_string/1)})"
      else
        "Nodes:          1 (local only)"
      end

    Mix.shell().info("""

    ==========================================
      Tetris Battle Bot Weight Evolution
    ==========================================
    Population:     #{config.population_size}
    Generations:    #{config.generations}
    Battles/genome: #{config.battles_per_genome}
    Concurrency:    #{config.max_concurrency}
    Total battles:  #{total_battles}
    Stagnation:     switch to co-evo after #{config.stagnation_threshold} flat gens
    Regression:     revert after #{config.regression_threshold} declining gens
    #{node_info}
    """)
  end

  defp print_generation(stats) do
    w = stats.best_genome
    mode = Map.get(stats, :opponent_mode, :solo_opponents)

    mode_tag =
      case mode do
        :co_evolution -> "[co-evo]"
        _ -> "[solo  ]"
      end

    msg =
      :io_lib.format(
        "Gen ~3B ~s | Best: ~6.2f | Avg: ~6.2f | " <>
          "h=~.2f o=~.2f b=~.2f l=~.2f gp=~.2f ab=~.2f tb=~.2f sh=~.2f",
        [
          stats.generation,
          mode_tag,
          stats.best_fitness,
          stats.avg_fitness,
          w.height,
          w.holes,
          w.bumpiness,
          w.lines,
          w.garbage_pressure,
          w.attack_bonus,
          w.tetris_bonus,
          w.survival_height
        ]
      )

    Mix.shell().info(IO.chardata_to_string(msg))
  end

  defp init_csv(path) do
    header =
      "generation,opponent_mode,best_fitness,avg_fitness,worst_fitness," <>
        "height,holes,bumpiness,lines,max_height,wells," <>
        "row_transitions,column_transitions," <>
        "garbage_pressure,attack_bonus,danger_aggression," <>
        "survival_height,tetris_bonus,line_efficiency\n"

    File.write!(path, header)
  end

  defp append_csv(path, stats) do
    w = stats.best_genome
    mode = Map.get(stats, :opponent_mode, :solo_opponents)

    row =
      :io_lib.format(
        "~B,~s,~.4f,~.4f,~.4f," <>
          "~.4f,~.4f,~.4f,~.4f,~.4f,~.4f," <>
          "~.4f,~.4f," <>
          "~.4f,~.4f,~.4f,~.4f,~.4f,~.4f~n",
        [
          stats.generation,
          mode,
          stats.best_fitness,
          stats.avg_fitness,
          stats.worst_fitness,
          w.height,
          w.holes,
          w.bumpiness,
          w.lines,
          w.max_height,
          w.wells,
          w.row_transitions,
          w.column_transitions,
          w.garbage_pressure,
          w.attack_bonus,
          w.danger_aggression,
          w.survival_height,
          w.tetris_bonus,
          w.line_efficiency
        ]
      )

    File.write!(path, IO.chardata_to_string(row), [:append])
  end

  defp save_json(path, genome, fitness, config) do
    data = %{
      weights: %{
        height: Float.round(genome.height, 4),
        holes: Float.round(genome.holes, 4),
        bumpiness: Float.round(genome.bumpiness, 4),
        lines: Float.round(genome.lines, 4),
        max_height: Float.round(genome.max_height, 4),
        wells: Float.round(genome.wells, 4),
        row_transitions: Float.round(genome.row_transitions, 4),
        column_transitions: Float.round(genome.column_transitions, 4),
        garbage_pressure: Float.round(genome.garbage_pressure, 4),
        attack_bonus: Float.round(genome.attack_bonus, 4),
        danger_aggression: Float.round(genome.danger_aggression, 4),
        survival_height: Float.round(genome.survival_height, 4),
        tetris_bonus: Float.round(genome.tetris_bonus, 4),
        line_efficiency: Float.round(genome.line_efficiency, 4)
      },
      fitness: Float.round(fitness, 4),
      config: %{
        population_size: config.population_size,
        generations: config.generations,
        battles_per_genome: config.battles_per_genome
      },
      evolved_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(path, json)
  end

  defp print_chart(stats) when length(stats) < 2 do
    Mix.shell().info("\nNot enough data for chart.")
  end

  defp print_chart(stats) do
    best_vals = Enum.map(stats, & &1.best_fitness)
    avg_vals = Enum.map(stats, & &1.avg_fitness)
    max_val = max(best_vals |> Enum.max() |> Float.ceil() |> trunc(), 1)
    chart_width = 60
    chart_height = 10
    num_gens = length(stats)

    Mix.shell().info("\nFitness over generations:")

    for row <- chart_height..0//-1 do
      threshold = max_val * row / chart_height
      label = threshold |> Float.round(0) |> trunc() |> Integer.to_string() |> String.pad_leading(4)
      line = render_chart_line(best_vals, avg_vals, chart_width, num_gens, threshold)
      Mix.shell().info("#{label} |#{line}")
    end

    Mix.shell().info("     +" <> String.duplicate("-", chart_width))
    Mix.shell().info("      #{gen_label_line(num_gens, chart_width)}")
    Mix.shell().info("           ---- Best    .... Average")
  end

  defp render_chart_line(best_vals, avg_vals, chart_width, num_gens, threshold) do
    for col <- 0..(chart_width - 1), into: "" do
      gen_idx = trunc(col * (num_gens - 1) / max(chart_width - 1, 1))
      best_v = Enum.at(best_vals, gen_idx, 0.0)
      avg_v = Enum.at(avg_vals, gen_idx, 0.0)
      chart_cell(best_v, avg_v, threshold)
    end
  end

  defp chart_cell(best_v, _avg_v, threshold) when best_v >= threshold, do: "*"
  defp chart_cell(_best_v, avg_v, threshold) when avg_v >= threshold, do: "."
  defp chart_cell(_best_v, _avg_v, _threshold), do: " "

  defp gen_label_line(num_gens, chart_width) do
    step = max(div(num_gens, 5), 1)

    labels =
      0..num_gens//step
      |> Enum.map(&Integer.to_string/1)

    Enum.join(
      labels,
      String.duplicate(" ", max(div(chart_width, length(labels)) - 2, 1))
    )
  end

  defp print_summary(genome, fitness, output_path, log_path) do
    Mix.shell().info("""

    ==========================================
      Evolution Complete
    ==========================================
    Best fitness: #{Float.round(fitness, 4)}
    Weights:
      height:             #{Float.round(genome.height, 4)}
      holes:              #{Float.round(genome.holes, 4)}
      bumpiness:          #{Float.round(genome.bumpiness, 4)}
      lines:              #{Float.round(genome.lines, 4)}
      max_height:         #{Float.round(genome.max_height, 4)}
      wells:              #{Float.round(genome.wells, 4)}
      row_transitions:    #{Float.round(genome.row_transitions, 4)}
      column_transitions: #{Float.round(genome.column_transitions, 4)}
      garbage_pressure:   #{Float.round(genome.garbage_pressure, 4)}
      attack_bonus:       #{Float.round(genome.attack_bonus, 4)}
      danger_aggression:  #{Float.round(genome.danger_aggression, 4)}
      survival_height:    #{Float.round(genome.survival_height, 4)}
      tetris_bonus:       #{Float.round(genome.tetris_bonus, 4)}
      line_efficiency:    #{Float.round(genome.line_efficiency, 4)}

    Saved to: #{output_path}
    CSV log:  #{log_path}
    """)
  end
end
