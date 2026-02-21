defmodule TetrisWeb.ChannelCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      @endpoint TetrisWeb.Endpoint
    end
  end

  setup tags do
    Platform.DataCase.setup_sandbox(tags)
    :ok
  end
end
