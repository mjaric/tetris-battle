defmodule BotTrainer.Evolution do
  @moduledoc """
  Genetic algorithm engine for evolving Tetris bot heuristic weights.

  Supports solo mode (6-weight genomes) and battle mode (12-weight
  genomes with adaptive opponent strategy).

  Pure functional — accepts a callback for progress reporting.
  """

  alias BotTrainer.BattleSimulation
  alias BotTrainer.Simulation

  @weight_keys [
    :height,
    :holes,
    :bumpiness,
    :lines,
    :max_height,
    :wells
  ]

  @battle_weight_keys [
    :height,
    :holes,
    :bumpiness,
    :lines,
    :max_height,
    :wells,
    :garbage_incoming,
    :garbage_send,
    :tetris_bonus,
    :opponent_danger,
    :survival,
    :line_efficiency
  ]

  @type genome :: %{
          height: float(),
          holes: float(),
          bumpiness: float(),
          lines: float(),
          max_height: float(),
          wells: float()
        }

  @type scored :: {float(), genome()}

  @type config :: %{
          population_size: pos_integer(),
          generations: pos_integer(),
          games_per_genome: pos_integer(),
          tournament_size: pos_integer(),
          crossover_rate: float(),
          mutation_rate: float(),
          mutation_sigma: float(),
          elitism_count: non_neg_integer(),
          immigrant_count: non_neg_integer(),
          max_concurrency: pos_integer()
        }

  @type gen_stats :: %{
          generation: pos_integer(),
          best_fitness: float(),
          avg_fitness: float(),
          worst_fitness: float(),
          best_genome: genome()
        }

  # -----------------------------------------------------------
  # Solo evolution (existing API — unchanged)
  # -----------------------------------------------------------

  @doc """
  Returns default GA configuration.
  """
  @spec default_config() :: config()
  def default_config do
    %{
      population_size: 50,
      generations: 100,
      games_per_genome: 10,
      tournament_size: 3,
      crossover_rate: 0.7,
      mutation_rate: 0.3,
      mutation_sigma: 0.15,
      elitism_count: 2,
      immigrant_count: 5,
      max_concurrency: System.schedulers_online()
    }
  end

  @doc """
  Generates a random population of N genomes, each normalized.
  """
  @spec random_population(pos_integer()) :: [genome()]
  def random_population(n) do
    Enum.map(1..n, fn _ -> random_genome() end)
  end

  @doc """
  Evaluates all genomes in parallel, returning `[{fitness, genome}]`
  sorted by fitness descending.
  """
  @spec evaluate_population(
          [genome()],
          pos_integer(),
          pos_integer(),
          keyword()
        ) :: [scored()]
  def evaluate_population(
        genomes,
        games_per_genome,
        max_concurrency,
        sim_opts \\ []
      ) do
    nodes = BotTrainer.Cluster.available_nodes()
    node_count = length(nodes)

    genomes
    |> Enum.with_index()
    |> Task.async_stream(
      fn {genome, idx} ->
        target = Enum.at(nodes, rem(idx, node_count))

        fitness =
          :erpc.call(
            target,
            Simulation,
            :evaluate,
            [genome, games_per_genome, sim_opts],
            :infinity
          )

        {fitness, genome}
      end,
      max_concurrency: max_concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.sort_by(fn {fitness, _} -> fitness end, :desc)
  end

  @doc """
  Runs the full GA loop. Calls `on_generation` after each generation
  with `gen_stats`. Returns the best genome found.
  """
  @spec evolve(config(), (gen_stats() -> any())) :: genome()
  def evolve(config, on_generation \\ fn _ -> :ok end) do
    population = random_population(config.population_size)
    evolve_loop(population, config, on_generation, 1)
  end

  @doc """
  Tournament selection: pick `k` random individuals, return fittest.
  """
  @spec tournament_select([scored()], pos_integer()) :: genome()
  def tournament_select(scored_pop, tournament_size) do
    scored_pop
    |> Enum.take_random(tournament_size)
    |> Enum.max_by(fn {fitness, _} -> fitness end)
    |> elem(1)
  end

  @doc """
  Uniform crossover: each weight randomly from parent A or B.
  """
  @spec crossover(genome(), genome()) :: genome()
  def crossover(parent_a, parent_b) do
    Map.new(@weight_keys, fn key ->
      {key, pick(parent_a[key], parent_b[key])}
    end)
  end

  @doc """
  Gaussian mutation: each weight mutated with probability `rate`.
  """
  @spec mutate(genome(), float(), float()) :: genome()
  def mutate(genome, rate, sigma) do
    Map.new(@weight_keys, fn key ->
      {key, maybe_mutate(genome[key], rate, sigma)}
    end)
  end

  @doc """
  Normalizes genome weights to sum to 1.0.
  Handles all-zero edge case by assigning equal weights.
  """
  @spec normalize(genome()) :: genome()
  def normalize(genome) do
    normalize_keys(genome, @weight_keys)
  end

  # -----------------------------------------------------------
  # Generalized normalize (works with any key list)
  # -----------------------------------------------------------

  @doc """
  Normalizes the given keys in a genome map so they sum to 1.0.
  Assigns equal weights when all values are zero.
  """
  @spec normalize_keys(map(), [atom()]) :: map()
  def normalize_keys(genome, keys) do
    total =
      Enum.reduce(keys, 0.0, fn k, acc -> acc + genome[k] end)

    n = length(keys)

    if total == 0.0 do
      Map.new(keys, fn k -> {k, 1.0 / n} end)
    else
      Map.new(keys, fn k -> {k, genome[k] / total} end)
    end
  end

  # -----------------------------------------------------------
  # Battle evolution
  # -----------------------------------------------------------

  @doc """
  Returns default configuration for battle evolution.
  """
  @spec default_battle_config() :: map()
  def default_battle_config do
    %{
      population_size: 50,
      generations: 100,
      battles_per_genome: 10,
      num_opponents: 3,
      tournament_size: 3,
      crossover_rate: 0.7,
      mutation_rate: 0.3,
      mutation_sigma: 0.15,
      elitism_count: 2,
      immigrant_count: 5,
      max_concurrency: System.schedulers_online(),
      stagnation_threshold: 5,
      regression_threshold: 3,
      lookahead: true
    }
  end

  @doc """
  Generates N random battle genomes with all 12 weight keys,
  normalized to sum to 1.0.
  """
  @spec random_battle_population(pos_integer()) :: [map()]
  def random_battle_population(n) do
    Enum.map(1..n, fn _ -> random_battle_genome() end)
  end

  @doc """
  Runs battle evolution with adaptive opponent strategy.

  Starts with solo opponents, switches to co-evolution on
  stagnation, and falls back on regression. Returns the best
  battle genome found.
  """
  @spec evolve_battle(map(), (gen_stats() -> any())) :: map()
  def evolve_battle(config, on_generation \\ fn _ -> :ok end) do
    population = random_battle_population(config.population_size)
    solo_hard = load_solo_hard_weights()

    adaptor = %{
      mode: :solo_opponents,
      stagnation_count: 0,
      regression_count: 0,
      best_fitness: nil,
      best_genome: nil
    }

    evolve_battle_loop(
      population,
      config,
      on_generation,
      solo_hard,
      adaptor,
      1
    )
  end

  # -----------------------------------------------------------
  # Solo evolution loop (unchanged)
  # -----------------------------------------------------------

  defp evolve_loop(population, config, _on_generation, gen)
       when gen > config.generations do
    sim_opts = sim_opts(config)

    scored =
      evaluate_population(
        population,
        config.games_per_genome,
        config.max_concurrency,
        sim_opts
      )

    {_fitness, best} = hd(scored)
    best
  end

  defp evolve_loop(population, config, on_generation, gen) do
    sim_opts = sim_opts(config)

    scored =
      evaluate_population(
        population,
        config.games_per_genome,
        config.max_concurrency,
        sim_opts
      )

    fitnesses = Enum.map(scored, fn {f, _} -> f end)

    stats = %{
      generation: gen,
      best_fitness: hd(fitnesses),
      avg_fitness: Enum.sum(fitnesses) / length(fitnesses),
      worst_fitness: List.last(fitnesses),
      best_genome: elem(hd(scored), 1)
    }

    on_generation.(stats)

    elites =
      scored
      |> Enum.take(config.elitism_count)
      |> Enum.map(fn {_, g} -> g end)

    children_needed =
      config.population_size - config.elitism_count -
        config.immigrant_count

    children =
      if children_needed > 0 do
        Enum.map(1..children_needed, fn _ ->
          if :rand.uniform() < config.crossover_rate do
            a = tournament_select(scored, config.tournament_size)
            b = tournament_select(scored, config.tournament_size)
            crossover(a, b)
          else
            tournament_select(scored, config.tournament_size)
          end
          |> mutate(config.mutation_rate, config.mutation_sigma)
          |> normalize()
        end)
      else
        []
      end

    immigrants = random_population(config.immigrant_count)
    next_pop = elites ++ children ++ immigrants
    evolve_loop(next_pop, config, on_generation, gen + 1)
  end

  # -----------------------------------------------------------
  # Battle evolution loop
  # -----------------------------------------------------------

  defp evolve_battle_loop(
         population,
         config,
         _on_generation,
         solo_hard,
         adaptor,
         gen
       )
       when gen > config.generations do
    sim_opts = sim_opts(config)
    opponents = build_opponents(adaptor, solo_hard)

    scored =
      evaluate_battle_population(
        population,
        opponents,
        config,
        sim_opts
      )

    case scored do
      [{_fitness, best} | _] -> best
      [] -> adaptor.best_genome || hd(population)
    end
  end

  defp evolve_battle_loop(
         population,
         config,
         on_generation,
         solo_hard,
         adaptor,
         gen
       ) do
    sim_opts = sim_opts(config)
    opponents = build_opponents(adaptor, solo_hard)

    scored =
      evaluate_battle_population(
        population,
        opponents,
        config,
        sim_opts
      )

    fitnesses = Enum.map(scored, fn {f, _} -> f end)
    best_fitness = hd(fitnesses)
    best_genome = elem(hd(scored), 1)

    stats = %{
      generation: gen,
      best_fitness: best_fitness,
      avg_fitness: Enum.sum(fitnesses) / length(fitnesses),
      worst_fitness: List.last(fitnesses),
      best_genome: best_genome
    }

    on_generation.(stats)

    adaptor =
      update_adaptor(
        adaptor,
        best_fitness,
        best_genome,
        config
      )

    elites =
      scored
      |> Enum.take(config.elitism_count)
      |> Enum.map(fn {_, g} -> g end)

    children_needed =
      config.population_size - config.elitism_count -
        config.immigrant_count

    children =
      if children_needed > 0 do
        Enum.map(1..children_needed, fn _ ->
          child =
            if :rand.uniform() < config.crossover_rate do
              a =
                tournament_select(scored, config.tournament_size)

              b =
                tournament_select(scored, config.tournament_size)

              crossover_keys(a, b, @battle_weight_keys)
            else
              tournament_select(scored, config.tournament_size)
            end

          child
          |> mutate_keys(
            config.mutation_rate,
            config.mutation_sigma,
            @battle_weight_keys
          )
          |> normalize_keys(@battle_weight_keys)
        end)
      else
        []
      end

    immigrants = random_battle_population(config.immigrant_count)
    next_pop = elites ++ children ++ immigrants

    evolve_battle_loop(
      next_pop,
      config,
      on_generation,
      solo_hard,
      adaptor,
      gen + 1
    )
  end

  # -----------------------------------------------------------
  # Battle evaluation
  # -----------------------------------------------------------

  defp evaluate_battle_population(
         genomes,
         opponents,
         config,
         sim_opts
       ) do
    nodes = BotTrainer.Cluster.available_nodes()
    node_count = length(nodes)
    battles = Map.get(config, :battles_per_genome, 10)
    concurrency = config.max_concurrency

    genomes
    |> Enum.with_index()
    |> Task.async_stream(
      fn {genome, idx} ->
        target = Enum.at(nodes, rem(idx, node_count))

        fitness =
          :erpc.call(
            target,
            BattleSimulation,
            :evaluate,
            [genome, opponents, battles, sim_opts],
            :infinity
          )

        {fitness, genome}
      end,
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.sort_by(fn {fitness, _} -> fitness end, :desc)
  end

  # -----------------------------------------------------------
  # Adaptive opponent strategy
  # -----------------------------------------------------------

  defp build_opponents(adaptor, solo_hard) do
    case adaptor.mode do
      :solo_opponents ->
        solo_list =
          if is_list(solo_hard), do: solo_hard, else: [solo_hard]

        fill_opponents(solo_list, 3)

      :co_evolution ->
        best = adaptor.best_genome
        random = random_battle_genome()

        solo_w =
          if is_list(solo_hard), do: hd(solo_hard), else: solo_hard

        [best, random, solo_w]
    end
  end

  defp fill_opponents(base, count) do
    Stream.cycle(base) |> Enum.take(count)
  end

  defp update_adaptor(adaptor, best_fitness, best_genome, config) do
    stag_thresh = config.stagnation_threshold
    reg_thresh = config.regression_threshold

    adaptor = %{adaptor | best_genome: best_genome}

    case adaptor.best_fitness do
      nil ->
        %{adaptor | best_fitness: best_fitness}

      prev ->
        improvement = (best_fitness - prev) / max(abs(prev), 1.0)
        stagnated = improvement < 0.01
        regressed = improvement < -0.05

        adaptor = %{adaptor | best_fitness: best_fitness}

        adaptor =
          if stagnated do
            %{adaptor | stagnation_count: adaptor.stagnation_count + 1}
          else
            %{adaptor | stagnation_count: 0}
          end

        adaptor =
          if regressed do
            %{adaptor | regression_count: adaptor.regression_count + 1}
          else
            %{adaptor | regression_count: 0}
          end

        cond do
          adaptor.mode == :co_evolution and
              adaptor.regression_count >= reg_thresh ->
            %{adaptor | mode: :solo_opponents, regression_count: 0}

          adaptor.mode == :solo_opponents and
              adaptor.stagnation_count >= stag_thresh ->
            %{adaptor | mode: :co_evolution, stagnation_count: 0}

          true ->
            adaptor
        end
    end
  end

  # -----------------------------------------------------------
  # Battle-specific crossover and mutation
  # -----------------------------------------------------------

  defp crossover_keys(parent_a, parent_b, keys) do
    Map.new(keys, fn key ->
      {key, pick(parent_a[key], parent_b[key])}
    end)
  end

  defp mutate_keys(genome, rate, sigma, keys) do
    Map.new(keys, fn key ->
      {key, maybe_mutate(genome[key], rate, sigma)}
    end)
  end

  # -----------------------------------------------------------
  # Load solo hard weights for opponent baseline
  # -----------------------------------------------------------

  defp load_solo_hard_weights do
    Tetris.BotStrategy.weights_for(:hard)
  rescue
    _ ->
      %{
        height: 0.51,
        holes: 0.36,
        bumpiness: 0.18,
        lines: 0.76,
        max_height: 0.0,
        wells: 0.0
      }
  end

  # -----------------------------------------------------------
  # Shared helpers
  # -----------------------------------------------------------

  defp sim_opts(config) do
    [lookahead: Map.get(config, :lookahead, true)]
  end

  defp random_genome do
    genome =
      Map.new(@weight_keys, fn k -> {k, :rand.uniform()} end)

    normalize(genome)
  end

  defp random_battle_genome do
    genome =
      Map.new(@battle_weight_keys, fn k ->
        {k, :rand.uniform()}
      end)

    normalize_keys(genome, @battle_weight_keys)
  end

  defp pick(a, b) do
    if :rand.uniform() < 0.5, do: a, else: b
  end

  defp maybe_mutate(value, rate, sigma) do
    if :rand.uniform() < rate do
      noise = :rand.normal() * sigma
      clamp(value + noise, 0.0, 1.0)
    else
      value
    end
  end

  defp clamp(val, min_val, max_val) do
    val |> max(min_val) |> min(max_val)
  end
end
