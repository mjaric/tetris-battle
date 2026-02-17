defmodule BotTrainer.Evolution do
  @moduledoc """
  Genetic algorithm engine for evolving Tetris bot heuristic weights.

  Pure functional — accepts a callback for progress reporting.
  """

  alias BotTrainer.Simulation

  @weight_keys [:height, :holes, :bumpiness, :lines, :max_height, :wells]

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
  def evaluate_population(genomes, games_per_genome, max_concurrency, sim_opts \\ []) do
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
    total =
      Enum.reduce(@weight_keys, 0.0, fn k, acc ->
        acc + genome[k]
      end)

    n = length(@weight_keys)

    if total == 0.0 do
      Map.new(@weight_keys, fn k -> {k, 1.0 / n} end)
    else
      Map.new(@weight_keys, fn k -> {k, genome[k] / total} end)
    end
  end

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

  defp sim_opts(config) do
    [lookahead: Map.get(config, :lookahead, true)]
  end

  defp random_genome do
    genome =
      Map.new(@weight_keys, fn k -> {k, :rand.uniform()} end)

    normalize(genome)
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
