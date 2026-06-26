defmodule ManaChessOnline.GameSupervisorTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameServer, GameState, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "starts a game server under the dynamic supervisor" do
    game_id = "supervised_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    {:ok, pid} = GameSupervisor.start_game(game, id: {__MODULE__, game_id})

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    assert GameServer.snapshot(pid).id == game_id
    assert GameSupervisor.child_count().active >= 1
  end
end
