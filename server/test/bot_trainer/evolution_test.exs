defmodule BotTrainer.EvolutionTest do
  use ExUnit.Case, async: true

  alias BotTrainer.Evolution

  @weights [:height, :holes, :bumpiness, :lines, :max_height, :wells]

  describe "random_population/1" do
    test "generates correct number of genomes" do
      pop = Evolution.random_population(10)
      assert length(pop) == 10
    end

    test "each genome has all weight keys" do
      [genome | _] = Evolution.random_population(1)

      for key <- @weights do
        assert Map.has_key?(genome, key)
        assert is_float(genome[key])
        assert genome[key] >= 0.0
      end
    end

    test "genomes are normalized to sum ~1.0" do
      pop = Evolution.random_population(20)

      for genome <- pop do
        total =
          Enum.reduce(@weights, 0.0, fn k, acc ->
            acc + genome[k]
          end)

        assert_in_delta total, 1.0, 0.001
      end
    end
  end

  describe "normalize/1" do
    test "scales weights to sum to 1.0" do
      genome = %{
        height: 2.0, holes: 3.0, bumpiness: 1.0,
        lines: 4.0, max_height: 0.0, wells: 0.0
      }

      normalized = Evolution.normalize(genome)

      total =
        Enum.reduce(@weights, 0.0, fn k, acc ->
          acc + normalized[k]
        end)

      assert_in_delta total, 1.0, 0.001
      assert_in_delta normalized.height, 0.2, 0.001
    end

    test "handles all-zero edge case" do
      genome = %{
        height: 0.0, holes: 0.0, bumpiness: 0.0,
        lines: 0.0, max_height: 0.0, wells: 0.0
      }

      normalized = Evolution.normalize(genome)
      n = length(@weights)

      for key <- @weights do
        assert_in_delta normalized[key], 1.0 / n, 0.001
      end
    end
  end

  describe "crossover/2" do
    test "child weights come from one of the parents" do
      a = %{
        height: 0.1, holes: 0.2, bumpiness: 0.3,
        lines: 0.4, max_height: 0.05, wells: 0.15
      }

      b = %{
        height: 0.5, holes: 0.6, bumpiness: 0.7,
        lines: 0.8, max_height: 0.35, wells: 0.45
      }

      child = Evolution.crossover(a, b)

      for key <- @weights do
        assert child[key] in [a[key], b[key]]
      end
    end
  end

  describe "mutate/3" do
    test "with rate 0 returns identical genome" do
      genome = %{
        height: 0.2, holes: 0.2, bumpiness: 0.2,
        lines: 0.2, max_height: 0.1, wells: 0.1
      }

      mutated = Evolution.mutate(genome, 0.0, 0.1)
      assert mutated == genome
    end

    test "with rate 1 modifies weights" do
      genome = %{
        height: 0.5, holes: 0.5, bumpiness: 0.5,
        lines: 0.5, max_height: 0.5, wells: 0.5
      }

      any_changed =
        Enum.any?(1..20, fn _ ->
          mutated = Evolution.mutate(genome, 1.0, 0.5)
          mutated != genome
        end)

      assert any_changed
    end

    test "clamps values to [0, 1]" do
      genome = %{
        height: 0.01, holes: 0.99, bumpiness: 0.5,
        lines: 0.5, max_height: 0.01, wells: 0.99
      }

      for _ <- 1..50 do
        mutated = Evolution.mutate(genome, 1.0, 1.0)

        for key <- @weights do
          assert mutated[key] >= 0.0
          assert mutated[key] <= 1.0
        end
      end
    end
  end

  describe "tournament_select/2" do
    test "returns a valid genome from the population" do
      genomes = Evolution.random_population(10)

      scored =
        Enum.map(genomes, fn g ->
          {:rand.uniform() * 100, g}
        end)

      selected = Evolution.tournament_select(scored, 3)

      assert Map.has_key?(selected, :height)
      assert selected in genomes
    end
  end

  describe "evolve/2" do
    test "tiny evolution run completes and returns valid genome" do
      config =
        Evolution.default_config()
        |> Map.merge(%{
          population_size: 6,
          generations: 2,
          games_per_genome: 1,
          elitism_count: 1,
          immigrant_count: 1,
          lookahead: false,
          max_concurrency: System.schedulers_online()
        })

      stats_log = :ets.new(:test_stats, [:bag, :public])

      best =
        Evolution.evolve(config, fn stats ->
          :ets.insert(stats_log, {stats.generation, stats})
        end)

      for key <- @weights do
        assert Map.has_key?(best, key)
        assert is_float(best[key])
      end

      all_stats = :ets.tab2list(stats_log)
      assert length(all_stats) == 2
      :ets.delete(stats_log)
    end
  end
end
