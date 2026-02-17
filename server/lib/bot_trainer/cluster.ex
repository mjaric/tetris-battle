defmodule BotTrainer.Cluster do
  @moduledoc """
  Manages distributed worker nodes for parallel bot evolution.

  Connects to remote BEAM nodes, pushes compiled modules, and
  provides helpers for distributing work across the cluster.
  """

  require Logger

  @modules_to_push [
    Tetris.Board,
    Tetris.BoardAnalysis,
    Tetris.Piece,
    Tetris.WallKicks,
    Tetris.BotStrategy,
    BotTrainer.Simulation
  ]

  @doc """
  Starts Erlang distribution on the local node if not already started.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec ensure_distribution(atom(), atom()) :: :ok | {:error, term()}
  def ensure_distribution(node_name, cookie) do
    if Node.alive?() do
      Node.set_cookie(cookie)
      :ok
    else
      ensure_epmd()

      case Node.start(node_name, :longnames) do
        {:ok, _pid} ->
          Node.set_cookie(cookie)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp ensure_epmd do
    case System.cmd("epmd", ["-daemon"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  @doc """
  Connects to worker nodes and pushes compiled modules to each.

  Returns `{connected, failed}` lists.
  """
  @spec connect_workers([atom()]) :: {[atom()], [atom()]}
  def connect_workers(worker_nodes) do
    results =
      Enum.map(worker_nodes, fn worker ->
        case Node.connect(worker) do
          true ->
            push_modules(worker)
            Logger.info("Connected to worker #{worker}, modules pushed")
            {:ok, worker}

          false ->
            Logger.warning("Failed to connect to worker #{worker}")
            {:error, worker}

          :ignored ->
            Logger.warning("Local node not alive, cannot connect to #{worker}")
            {:error, worker}
        end
      end)

    connected = for {:ok, w} <- results, do: w
    failed = for {:error, w} <- results, do: w
    {connected, failed}
  end

  @doc """
  Pushes all required compiled modules to a remote node.
  """
  @spec push_modules(atom()) :: :ok
  def push_modules(worker) do
    Enum.each(@modules_to_push, fn mod ->
      {^mod, binary, filename} = :code.get_object_code(mod)

      :rpc.call(
        worker,
        :code,
        :load_binary,
        [mod, filename, binary]
      )
    end)
  end

  @doc """
  Returns all available nodes (local + connected workers).
  """
  @spec available_nodes() :: [atom()]
  def available_nodes do
    [node() | Node.list()]
  end
end
