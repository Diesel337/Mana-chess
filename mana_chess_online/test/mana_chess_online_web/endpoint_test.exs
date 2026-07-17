defmodule ManaChessOnlineWeb.EndpointTest do
  use ExUnit.Case, async: true

  test "caps LiveView websocket frames and keeps compression disabled" do
    {"/live", Phoenix.LiveView.Socket, options} =
      Enum.find(ManaChessOnlineWeb.Endpoint.__sockets__(), fn {path, _socket, _options} ->
        path == "/live"
      end)

    websocket_options = Keyword.fetch!(options, :websocket)

    refute Keyword.fetch!(websocket_options, :log)
    assert Keyword.fetch!(websocket_options, :max_frame_size) == 1_000_000
    refute Keyword.fetch!(websocket_options, :compress)
  end

  test "disables high-volume request and socket logs outside development" do
    assert ManaChessOnlineWeb.Endpoint.routine_log_levels() == %{
             request: false,
             socket: false
           }
  end

  test "vendored realtime clients match the installed Phoenix dependencies" do
    root = Path.expand("../..", __DIR__)

    [
      {"deps/phoenix/priv/static/phoenix.js", "priv/static/assets/js/phoenix.js"},
      {"deps/phoenix_live_view/priv/static/phoenix_live_view.js",
       "priv/static/assets/js/phoenix_live_view.js"}
    ]
    |> Enum.each(fn {source, destination} ->
      assert File.read!(Path.join(root, destination)) == File.read!(Path.join(root, source))
    end)
  end
end
