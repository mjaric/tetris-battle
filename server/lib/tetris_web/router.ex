defmodule TetrisWeb.Router do
  use Phoenix.Router
  import Plug.Conn

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/auth", PlatformWeb do
    pipe_through(:browser)

    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
  end

  scope "/api/auth", PlatformWeb do
    pipe_through(:api)

    post("/guest", AuthController, :guest)
    post("/refresh", AuthController, :refresh)
    post("/register", AuthController, :register)
    get("/check-nickname/:nickname", AuthController, :check_nickname)
  end

  scope "/api", TetrisWeb do
    pipe_through(:api)
  end

  scope "/", TetrisWeb do
    get("/*path", PageController, :index)
  end
end
