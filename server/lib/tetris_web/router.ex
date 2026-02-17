defmodule TetrisWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", TetrisWeb do
    pipe_through(:api)
  end
end
