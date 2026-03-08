defmodule Mix.Tasks.TetrisGpt.Train do
  @shortdoc "Train TetrisGpt transformer model"

  @moduledoc """
  Trains the TetrisGpt model on recorded game data.

  ## Usage

      mix tetris_gpt.train --epochs 50

  ## Options

    * `--epochs` - Training epochs (default: 50)
    * `--batch-size` - Batch size (default: 32)
    * `--lr` - Learning rate (default: 3e-4)
    * `--data` - Training data path
      (default: priv/tetris_gpt/data/sequences.bin)
    * `--output` - Output directory for params
      (default: priv/tetris_gpt/checkpoints)
  """

  use Mix.Task

  alias TetrisGpt.Model.Transformer
  alias TetrisGpt.Training.{DataPipeline, Trainer}

  require Logger

  @switches [
    epochs: :integer,
    batch_size: :integer,
    lr: :float,
    data: :string,
    output: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, _, _} =
      OptionParser.parse(args, switches: @switches)

    epochs = Keyword.get(opts, :epochs, 50)
    batch_size = Keyword.get(opts, :batch_size, 32)
    lr = Keyword.get(opts, :lr, 3.0e-4)

    data_path =
      Keyword.get(
        opts,
        :data,
        "priv/tetris_gpt/data/sequences.bin"
      )

    output_dir =
      Keyword.get(opts, :output, "priv/tetris_gpt/checkpoints")

    Logger.info("Loading training data from #{data_path}...")
    sequences = DataPipeline.load(data_path)
    Logger.info("Loaded #{length(sequences)} sequences")

    sequences = Enum.shuffle(sequences)
    split = round(length(sequences) * 0.9)
    {train_seqs, _val_seqs} = Enum.split(sequences, split)

    Logger.info("Train: #{length(train_seqs)} sequences")

    batches =
      DataPipeline.batch_sequences(
        train_seqs,
        batch_size: batch_size
      )

    Logger.info("#{length(batches)} training batches")

    config = Transformer.default_config()
    model = Transformer.build(config)

    train_data =
      batches
      |> Stream.cycle()
      |> Stream.map(fn {input_map, target, _mask} ->
        {input_map, target}
      end)

    Logger.info("Starting training for #{epochs} epochs...")

    params =
      Trainer.train(
        model,
        train_data,
        epochs: epochs,
        learning_rate: lr
      )

    File.mkdir_p!(output_dir)
    final_path = Path.join(output_dir, "final_params.nx")

    Trainer.save_params(params, final_path)

    Logger.info("Training complete! Params saved to #{final_path}")
  end
end
