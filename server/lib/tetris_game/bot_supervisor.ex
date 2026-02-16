defmodule TetrisGame.BotSupervisor do
  @moduledoc """
  DynamicSupervisor for bot player processes.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new bot player under this supervisor.
  """
  @spec start_bot(keyword()) :: DynamicSupervisor.on_start_child()
  def start_bot(opts) do
    spec = %{
      id: Keyword.fetch!(opts, :bot_id),
      start: {TetrisGame.BotPlayer, :start_link, [opts]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a bot player process.
  """
  @spec stop_bot(pid()) :: :ok | {:error, :not_found}
  def stop_bot(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
