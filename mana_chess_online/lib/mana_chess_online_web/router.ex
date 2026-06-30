defmodule ManaChessOnlineWeb.Router do
  use ManaChessOnlineWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :ensure_player_id
    plug ManaChessOnlineWeb.LaunchAccessPlug
    plug :fetch_live_flash
    plug :put_root_layout, html: {ManaChessOnlineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ManaChessOnlineWeb do
    pipe_through :browser

    live "/", GameLive, :index
    live "/game/:game_id", GameLive, :show
    live "/admin", AdminLive, :index
  end

  defp ensure_player_id(conn, _opts) do
    case Plug.Conn.get_session(conn, :player_id) do
      nil -> Plug.Conn.put_session(conn, :player_id, random_player_id())
      _player_id -> conn
    end
  end

  defp random_player_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  # Other scopes may use custom stacks.
  # scope "/api", ManaChessOnlineWeb do
  #   pipe_through :api
  # end

  # Dev dashboard is intentionally disabled for this tiny prototype.
end
