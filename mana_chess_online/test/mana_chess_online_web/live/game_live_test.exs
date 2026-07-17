defmodule ManaChessOnlineWeb.GameLiveTest do
  use ManaChessOnlineWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ManaChessOnline.{GameLobby, GameSupervisor}

  setup do
    original_config = Application.get_env(:mana_chess_online, :launch_access)

    on_exit(fn ->
      if original_config do
        Application.put_env(:mana_chess_online, :launch_access, original_config)
      else
        Application.delete_env(:mana_chess_online, :launch_access)
      end
    end)

    Application.put_env(:mana_chess_online, :launch_access, mode: "open", qa_bypass_key: "")

    :ok
  end

  test "forged clear room events cannot clear rooms for unseated players", %{conn: conn} do
    owner_id = "live-clear-owner"
    intruder_id = "live-clear-intruder"
    game_id = "game_4"

    on_exit(fn ->
      GameLobby.force_clear_room(game_id)
    end)

    GameLobby.force_clear_room(game_id)
    assert %{game_id: ^game_id} = GameLobby.sit(owner_id, game_id, :white)
    before_game = GameLobby.snapshot(game_id)

    conn = Plug.Test.init_test_session(conn, player_id: intruder_id)
    {:ok, view, _html} = live(conn, ~p"/")

    refute render(view) =~ ~s(phx-click="clear_room")
    render_click(view, "clear_room", %{"game" => game_id})

    after_game = GameLobby.snapshot(game_id)

    assert after_game.players == before_game.players
    assert after_game.status == before_game.status
    assert {:ok, _pid} = GameSupervisor.lookup_game(game_id)
  end

  test "lobby keeps play choices ahead of ranking and inline cosmetics", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    {offline_position, _} = :binary.match(html, ~s(class="mc-offline"))
    {lobby_position, _} = :binary.match(html, ~s(class="mc-lobby"))
    {ranking_position, _} = :binary.match(html, ~s(class="mc-ranking"))
    {cosmetics_position, _} = :binary.match(html, ~s(class="mc-skins mc-skins-inline"))

    assert offline_position < lobby_position
    assert lobby_position < ranking_position
    assert ranking_position < cosmetics_position
  end

  test "lobby renders the competitive profile and rated quick match action", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(data-competitive-rating)
    assert html =~ "Prov. 0/10"
    assert html =~ "Buscar rival"
    assert html =~ "Cerca de 1200"
    assert html =~ ~s(data-competitive-leaderboard)
    assert html =~ "Sin posicion"
  end

  test "leaderboard renders public aliases and the current rank without private ids", %{
    conn: conn
  } do
    original_persistence = Application.get_env(:mana_chess_online, :persistence)

    original_leaderboard =
      Application.get_env(:mana_chess_online, :persistence_test_competitive_leaderboard)

    on_exit(fn ->
      restore_env(:persistence, original_persistence)
      restore_env(:persistence_test_competitive_leaderboard, original_leaderboard)
    end)

    current_player_id = "steam_private_current"
    leader_player_id = "steam_private_leader"

    Application.put_env(:mana_chess_online, :persistence,
      enabled: true,
      store: ManaChessOnline.PersistenceTestStore,
      writer: ManaChessOnline.PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_competitive_leaderboard, %{
      entries: [rating_entry(leader_player_id, 1, 1_440, 12)],
      current: rating_entry(current_player_id, 7, 1_230, 3),
      total_players: 19
    })

    conn = Plug.Test.init_test_session(conn, player_id: current_player_id)
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ManaChessOnline.CompetitiveLeaderboard.alias_for(leader_player_id)
    assert html =~ "Tu puesto #7"
    assert html =~ "19 jugadores"
    refute html =~ leader_player_id
    refute html =~ current_player_id
  end

  defp rating_entry(player_id, rank, rating, games) do
    %{
      player_id: player_id,
      rank: rank,
      rating: rating,
      games_played: games,
      wins: games,
      losses: 0,
      draws: 0
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
