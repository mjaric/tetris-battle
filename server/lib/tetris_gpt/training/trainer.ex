defmodule TetrisGpt.Training.Trainer do
  @moduledoc """
  Training orchestration for TetrisGpt using Axon.Loop.

  Handles:
  - Loss computation (cross-entropy on placement predictions)
  - Optimizer setup (Adam via Polaris)
  - Metric tracking (loss per iteration)
  - Parameter save/load
  """

  require Logger

  @doc """
  Train the model on the given data stream.

  Data should be a stream of {input_map, target_tensor} tuples
  where:
    - input_map: %{"board" => ..., "current_piece" => ..., ...}
    - target_tensor: {batch, seq_len} int32 placement indices

  Options:
    - :epochs - number of epochs (default: 50)
    - :learning_rate - Adam learning rate (default: 3.0e-4)
    - :initial_params - resume from existing params (default: %{})

  Returns trained model parameters.
  """
  def train(model, train_data, opts \\ []) do
    epochs = Keyword.get(opts, :epochs, 50)
    lr = Keyword.get(opts, :learning_rate, 3.0e-4)
    iterations = Keyword.get(opts, :iterations)

    initial_params =
      Keyword.get(opts, :initial_params, Axon.ModelState.empty())

    optimizer = Polaris.Optimizers.adam(learning_rate: lr)

    run_opts =
      [epochs: epochs] ++
        if(iterations, do: [iterations: iterations], else: [])

    model
    |> Axon.Loop.trainer(
      &cross_entropy_loss/2,
      optimizer,
      log: 1
    )
    |> Axon.Loop.run(train_data, initial_params, run_opts)
  end

  @doc "Save model parameters to a file."
  def save_params(params, path) do
    File.mkdir_p!(Path.dirname(path))
    binary = Nx.serialize(params)
    File.write!(path, binary)
    Logger.info("Model params saved to #{path}")
  end

  @doc "Load model parameters from a file."
  def load_params(path) do
    path
    |> File.read!()
    |> Nx.deserialize()
  end

  defp cross_entropy_loss(y_true, y_pred) do
    # y_true: {batch, seq_len} (integer class indices)
    # y_pred: {batch, seq_len, num_classes} (softmax probs)
    {_batch, _seq_len, num_classes} = Nx.shape(y_pred)

    y_one_hot =
      Nx.equal(
        Nx.new_axis(y_true, -1),
        Nx.iota({num_classes})
      )
      |> Nx.as_type(:f32)

    eps = 1.0e-7
    log_probs = Nx.log(Nx.add(y_pred, eps))

    loss =
      Nx.negate(Nx.sum(Nx.multiply(y_one_hot, log_probs), axes: [-1]))

    Nx.mean(loss)
  end
end
