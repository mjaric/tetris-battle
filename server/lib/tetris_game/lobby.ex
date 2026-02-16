defmodule TetrisGame.Lobby do
  use GenServer

  defstruct rooms: %{}

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new room with the given options.

  Options:
    - `:host` - the player hosting the room (required)
    - `:name` - the room name (required)
    - `:max_players` - maximum number of players (required)
    - `:password` - optional room password
  """
  def create_room(opts) do
    GenServer.call(__MODULE__, {:create_room, opts})
  end

  @doc """
  Returns a list of all room info maps.
  """
  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  @doc """
  Returns `{:ok, room_info}` or `{:error, :not_found}` for the given room_id.
  """
  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id})
  end

  @doc """
  Removes a room from the lobby. This is a cast (fire-and-forget).
  """
  def remove_room(room_id) do
    GenServer.cast(__MODULE__, {:remove_room, room_id})
  end

  @doc """
  Updates room info with the given updates map.
  Returns `:ok` or `{:error, :not_found}`.
  """
  def update_room(room_id, updates) do
    GenServer.call(__MODULE__, {:update_room, room_id, updates})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:create_room, opts}, _from, state) do
    room_id = generate_room_id()

    room_opts = [
      host: opts.host,
      name: opts.name,
      max_players: opts.max_players
    ]

    room_opts =
      if Map.has_key?(opts, :password) do
        [{:password, opts.password} | room_opts]
      else
        room_opts
      end

    try do
      case TetrisGame.RoomSupervisor.start_room(room_id, room_opts) do
        {:ok, _pid} ->
          room_info = %{
            room_id: room_id,
            host: opts.host,
            name: opts.name,
            max_players: opts.max_players,
            has_password: Map.has_key?(opts, :password) and opts.password != nil,
            player_count: 0,
            status: :waiting
          }

          new_state = %{state | rooms: Map.put(state.rooms, room_id, room_info)}
          {:reply, {:ok, room_id}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    rescue
      e ->
        {:reply, {:error, Exception.message(e)}, state}
    end
  end

  def handle_call(:list_rooms, _from, state) do
    rooms = Map.values(state.rooms)
    {:reply, rooms, state}
  end

  def handle_call({:get_room, room_id}, _from, state) do
    case Map.fetch(state.rooms, room_id) do
      {:ok, room_info} ->
        {:reply, {:ok, room_info}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update_room, room_id, updates}, _from, state) do
    case Map.fetch(state.rooms, room_id) do
      {:ok, room_info} ->
        updated_info = Map.merge(room_info, updates)
        new_state = %{state | rooms: Map.put(state.rooms, room_id, updated_info)}
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_cast({:remove_room, room_id}, state) do
    new_state = %{state | rooms: Map.delete(state.rooms, room_id)}
    {:noreply, new_state}
  end

  # Private Functions

  defp generate_room_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
