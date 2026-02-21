defmodule PlatformWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import PlatformWeb.ConnCase

      @endpoint TetrisWeb.Endpoint
    end
  end

  setup tags do
    Platform.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
