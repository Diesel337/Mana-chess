defmodule ManaChessOnline.GamePersistenceTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GamePersistence, PersistenceTestWriter}

  setup do
    original_config = Application.get_env(:mana_chess_online, :persistence)
    original_pid = Application.get_env(:mana_chess_online, :persistence_test_pid)

    Application.put_env(:mana_chess_online, :persistence,
      enabled: false,
      store: ManaChessOnline.PersistenceTestStore,
      writer: PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_pid, self())

    on_exit(fn ->
      restore_env(:persistence, original_config)
      restore_env(:persistence_test_pid, original_pid)
    end)

    :ok
  end

  test "records exactly the transition into a terminal state" do
    playing = game(:playing)
    finished = game({:winner, :black})

    assert GamePersistence.observe(playing, finished) == finished
    assert_receive {:persistence_writer_event, {:match_summary, attrs}}
    assert attrs.result == "black_win"

    GamePersistence.observe(finished, %{finished | log: ["duplicate tick"]})
    refute_receive {:persistence_writer_event, _event}, 50
  end

  defp game(status) do
    %{
      id: "game_persistence_test",
      private?: false,
      practice?: false,
      status: status,
      players: %{white: "white", black: "black"},
      settings: %{},
      log: [],
      finished_at: 1_000
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
