defmodule ManaChessOnlineWeb.PageController do
  use ManaChessOnlineWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
