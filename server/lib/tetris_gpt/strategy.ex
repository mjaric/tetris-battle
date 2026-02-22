defmodule TetrisGpt.Strategy do
  @moduledoc """
  Behaviour for TetrisGpt model implementations.

  Each strategy encapsulates a difrent neural network architecture
  (or heruistic baseline) behind a uniform `predict/2` interface.
  The `GptBotPlayer` `GenServer` calls `predict/2` on each piece placement.
  """

  @typedoc """
  placement of the peice
  """
  @type placement :: %{rotation: 0..3, column: non_neg_integer()}
  @typedoc """
  This is just a parameter, concrete implementation of behaviour will
  have own type.
  """
  @type state :: term()
  @type context :: %{
          board: Nx.Tensor.t(),
          current_piece: atom(),
          next_piece: atom(),
          battle_context: map(),
          history: list(map())
        }

  @doc "Human readable name for logging and display."
  @callback name() :: String.t()

  @doc "Initialize strategy state. E.g. load model parameters etc."
  @callback init(opts :: keyword()) :: state()

  @doc """
  Given game context, it predicts the best placement.

  Returns the chose placement and update state. State is threded
  through calls to allow strategies to maintain internal buffers
  (e.g., the transformer's context window).
  """
  @callback predict(state(), context()) :: {placement(), state()}
end
