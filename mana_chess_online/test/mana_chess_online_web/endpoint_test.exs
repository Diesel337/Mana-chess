defmodule ManaChessOnlineWeb.EndpointTest do
  use ExUnit.Case, async: true

  test "caps LiveView websocket frames and keeps compression disabled" do
    {"/live", Phoenix.LiveView.Socket, options} =
      Enum.find(ManaChessOnlineWeb.Endpoint.__sockets__(), fn {path, _socket, _options} ->
        path == "/live"
      end)

    websocket_options = Keyword.fetch!(options, :websocket)

    assert Keyword.fetch!(websocket_options, :max_frame_size) == 1_000_000
    refute Keyword.fetch!(websocket_options, :compress)
  end
end
