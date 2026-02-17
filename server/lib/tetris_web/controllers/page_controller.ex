defmodule TetrisWeb.PageController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    path = Application.app_dir(:tetris, "priv/static/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, path)
  end
end
