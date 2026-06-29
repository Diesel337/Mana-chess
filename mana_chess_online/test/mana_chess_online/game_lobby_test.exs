defmodule ManaChessOnline.GameLobbyTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameLobby, GameServer, GameSupervisor}

  defp unique_player(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp flush_messages do
    receive do
      _message -> flush_messages()
    after
      0 -> :ok
    end
  end

  defp promotion_board do
    [
      ["P", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "K", ".", ".", "."]
    ]
  end

  test "exposes runtime metrics for admin health checks" do
    metrics = GameLobby.metrics()

    assert metrics.game_count >= 4
    assert metrics.public_game_count >= 4
    assert metrics.game_server_count >= 4
    assert metrics.memory_total_kb > 0
    assert metrics.process_count > 0
    assert is_integer(metrics.game_server_mailbox_total)
  end

  test "creates private games outside the public lobby and lets spectators watch by link" do
    player_id = unique_player("private-owner")
    on_exit(fn -> GameLobby.leave(player_id) end)

    {:ok, view} = GameLobby.create_private(player_id)

    assert String.starts_with?(view.game_id, "private_")
    assert view.color == :white
    refute Enum.any?(view.lobby, &(&1.id == view.game_id))

    game = GameLobby.snapshot(view.game_id)
    assert game.private?
    assert game.players.white == player_id
    assert game.players.black == nil

    spectator_view = GameLobby.watch(unique_player("spectator"), view.game_id)
    assert spectator_view.game_id == view.game_id
    assert spectator_view.color == nil
    assert spectator_view.game.private?
  end

  test "private matches become ready when black joins without entering public lobby" do
    white_id = unique_player("private-white")
    black_id = unique_player("private-black")

    on_exit(fn ->
      GameLobby.leave(white_id)
      GameLobby.leave(black_id)
    end)

    {:ok, white_view} = GameLobby.create_private(white_id)
    black_view = GameLobby.sit(black_id, white_view.game_id, :black)

    assert black_view.game_id == white_view.game_id
    assert black_view.color == :black

    game = GameLobby.snapshot(white_view.game_id)
    assert game.private?
    assert game.status == :ready
    assert game.players.white == white_id
    assert game.players.black == black_id
    refute Enum.any?(black_view.lobby, &(&1.id == white_view.game_id))
  end

  test "mirrors public seats when a player leaves" do
    player_id = unique_player("mirror-public-leave")
    view = GameLobby.sit(player_id, "game_1", :white)

    assert view.game_id == "game_1"
    assert {:ok, pid} = GameSupervisor.lookup_game("game_1")
    assert GameServer.snapshot(pid).players.white == player_id

    assert :ok = GameLobby.leave(player_id)
    assert GameServer.snapshot(pid).players.white == nil
  end

  test "practice games are isolated and removed when the player leaves" do
    player_id = unique_player("practice-player")
    view = GameLobby.start_practice(player_id)

    assert view.color == :practice
    assert view.game.practice?
    assert view.game.bot_enabled?
    assert view.game.players.white == player_id
    assert view.game.players.black == player_id

    assert :ok = GameLobby.leave(player_id)
    assert GameLobby.snapshot(view.game_id) == nil
  end

  test "practice can swap bot side so player can play black" do
    player_id = unique_player("practice-side")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert view.game.bot_color == :black

    view = GameLobby.toggle_practice_side(player_id)
    assert view.color == :practice
    assert view.game.bot_color == :white
    assert hd(view.game.log) == "Ahora juegas Negras; BOT controla Blancas."
  end

  test "mirrors practice games into registered game servers and removes them on leave" do
    player_id = unique_player("mirror-practice")
    view = GameLobby.start_practice(player_id)

    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)
    assert GameServer.snapshot(pid).id == view.game_id
    assert GameServer.snapshot(pid).players.white == player_id

    assert :ok = GameLobby.leave(player_id)
    assert GameSupervisor.lookup_game(view.game_id) == :error
  end

  test "mirrors practice bot toggles through the registered game server" do
    player_id = unique_player("mirror-bot-toggle")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    view = GameLobby.toggle_practice_bot(player_id)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    refute server_game.bot_enabled?
    assert server_game.bot_ready_at == nil
    assert server_game.bot_enabled? == lobby_game.bot_enabled?
    assert server_game.bot_ready_at == lobby_game.bot_ready_at
    assert server_game.log == lobby_game.log
  end

  test "mirrors practice side toggles through the registered game server" do
    player_id = unique_player("mirror-side-toggle")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)
    assert :ok = GameLobby.send_chat(player_id, view.game_id, "mantener chat")

    view = GameLobby.toggle_practice_side(player_id)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.bot_color == :white
    assert server_game.bot_color == lobby_game.bot_color
    assert server_game.chat == lobby_game.chat
    assert hd(server_game.chat).text == "mantener chat"
    assert server_game.log == lobby_game.log
  end

  test "mirrors practice settings updates through the registered game server" do
    player_id = unique_player("mirror-settings")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    assert :ok =
             GameLobby.update_settings(player_id, %{
               "max_elixir" => "12",
               "initial_elixir" => "6",
               "regen_per_second" => "1.5",
               "cooldown_seconds" => "2.25"
             })

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.settings == lobby_game.settings
    assert server_game.settings.max_elixir == 12.0
    assert server_game.elixir == %{white: 6.0, black: 6.0}
    assert server_game.elixir == lobby_game.elixir
    assert server_game.cooldowns == %{}
    assert server_game.log == lobby_game.log
  end

  test "mirrors reset requests through the registered game server" do
    white_id = unique_player("reset-white")
    black_id = unique_player("reset-black")

    on_exit(fn ->
      GameLobby.leave(white_id)
      GameLobby.leave(black_id)
    end)

    {:ok, white_view} = GameLobby.create_private(white_id)
    black_view = GameLobby.sit(black_id, white_view.game_id, :black)
    assert black_view.game.status == :ready
    assert {:ok, pid} = GameSupervisor.lookup_game(white_view.game_id)

    assert :ok = GameLobby.reset(white_id)

    lobby_game = :sys.get_state(GameLobby).games[white_view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.reset_requests == lobby_game.reset_requests
    assert MapSet.member?(server_game.reset_requests, white_id)
    assert server_game.log == lobby_game.log
    assert hd(server_game.log) == "Blancas pidio reiniciar la partida."
  end

  test "mirrors promotions through the registered game server" do
    player_id = unique_player("promote-player")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    :sys.replace_state(GameLobby, fn state ->
      game = state.games[view.game_id]

      game = %{
        game
        | board: promotion_board(),
          status: :promotion,
          promotion_pending: %{player_id: player_id, color: :white, at: {0, 0}},
          log: ["Promocion pendiente." | game.log]
      }

      put_in(state.games[view.game_id], game)
    end)

    assert :ok = GameLobby.promote(player_id, "Q")

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.board == lobby_game.board
    assert server_game.status == :playing
    assert server_game.status == lobby_game.status
    assert server_game.promotion_pending == nil
    assert server_game.promotion_pending == lobby_game.promotion_pending
    assert server_game.log == lobby_game.log
    assert hd(server_game.log) == "Blancas promociono peon."
    assert server_game.board |> Enum.at(0) |> Enum.at(0) == "Q"
  end

  test "mirrors player moves through the registered game server" do
    player_id = unique_player("mirror-move")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    assert :ok = GameLobby.enqueue(player_id, {6, 4}, {4, 4})

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.board == lobby_game.board
    assert server_game.elixir == lobby_game.elixir
    assert server_game.cooldowns == lobby_game.cooldowns
    assert server_game.queue == lobby_game.queue
    assert server_game.log == lobby_game.log
  end

  test "mirrors rejected moves through the registered game server" do
    player_id = unique_player("mirror-rejected-move")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    assert :ok = GameLobby.enqueue(player_id, {4, 4}, {3, 4})

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.board == lobby_game.board
    assert server_game.queue == lobby_game.queue
    assert server_game.log == lobby_game.log
    assert hd(server_game.log) == "Movimiento rechazado: no hay pieza en origen {4, 4}."
  end

  test "idle ticks do not broadcast unchanged lobby or room payloads" do
    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.lobby_topic())
    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic("game_1"))
    flush_messages()

    send(Process.whereis(GameLobby), :tick)
    :sys.get_state(GameLobby)

    refute_receive {:game_update, %{id: "game_1"}}, 75
    refute_receive {:lobby_update, _lobby}, 75
  end

  test "stores sanitized room chat messages" do
    player_id = unique_player("chat-player")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)

    assert :ok = GameLobby.send_chat(player_id, view.game_id, "  hola\n   mana   ")

    game = GameLobby.snapshot(view.game_id)

    assert [
             %{
               player_id: ^player_id,
               name: name,
               role: "Practica",
               sent_at: sent_at,
               text: "hola mana"
             }
             | _rest
           ] = game.chat

    assert String.starts_with?(name, "Jugador ")
    assert is_integer(sent_at)
  end

  test "mirrors room chat through the registered game server" do
    player_id = unique_player("chat-mirror")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    assert :ok = GameLobby.send_chat(player_id, view.game_id, "hola desde server")

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.chat == lobby_game.chat
    assert hd(server_game.chat).text == "hola desde server"
  end

  test "mirrors countdown readiness through the registered game server" do
    white_id = unique_player("start-white")
    black_id = unique_player("start-black")

    on_exit(fn ->
      GameLobby.leave(white_id)
      GameLobby.leave(black_id)
    end)

    {:ok, white_view} = GameLobby.create_private(white_id)
    black_view = GameLobby.sit(black_id, white_view.game_id, :black)
    assert black_view.game.status == :ready
    assert {:ok, pid} = GameSupervisor.lookup_game(white_view.game_id)

    assert :ok = GameLobby.start_game(white_id)

    lobby_game = :sys.get_state(GameLobby).games[white_view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.status == lobby_game.status
    assert MapSet.member?(server_game.start_requests, white_id)
    assert server_game.log == lobby_game.log

    assert :ok = GameLobby.ready_to_start(black_id)

    lobby_game = :sys.get_state(GameLobby).games[white_view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.status == :playing
    assert server_game.status == lobby_game.status
    assert server_game.start_requests == MapSet.new()
    assert server_game.log == lobby_game.log
  end

  test "keeps only the latest room chat messages in newest-first order" do
    player_id = unique_player("chat-limit")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)

    for number <- 1..30 do
      assert :ok = GameLobby.send_chat(player_id, view.game_id, "msg #{number}")
    end

    messages = GameLobby.snapshot(view.game_id).chat
    assert length(messages) == 24
    assert hd(messages).text == "msg 30"
    assert List.last(messages).text == "msg 7"
    refute Enum.any?(messages, &(&1.text == "msg 1"))
  end

  test "rate limits bursty room chat" do
    player_id = unique_player("chat-rate")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)

    for number <- 1..30 do
      assert :ok = GameLobby.send_chat(player_id, view.game_id, "burst #{number}")
    end

    assert {:error, :rate_limited} = GameLobby.send_chat(player_id, view.game_id, "one too many")
  end

  test "rate limits repeated private room creation" do
    player_id = unique_player("private-rate")
    on_exit(fn -> GameLobby.leave(player_id) end)

    for _number <- 1..3 do
      assert {:ok, view} = GameLobby.create_private(player_id)
      assert String.starts_with?(view.game_id, "private_")
    end

    assert {:error, :rate_limited} = GameLobby.create_private(player_id)
  end

  test "rate limits repeated lobby reconnect checks softly" do
    player_id = unique_player("join-rate")

    for _number <- 1..120 do
      view = GameLobby.join(player_id)
      assert is_list(view.lobby)
    end

    limited_view = GameLobby.join(player_id)
    assert is_list(limited_view.lobby)
  end

  test "rate limits repeated seat requests without moving the player again" do
    player_id = unique_player("seat-rate")
    on_exit(fn -> GameLobby.leave(player_id) end)

    for _number <- 1..30 do
      view = GameLobby.sit(player_id, "game_1", :white)
      assert view.game_id == "game_1"
    end

    limited_view = GameLobby.sit(player_id, "game_2", :black)
    assert limited_view.game_id == "game_1"
    assert limited_view.color == :white
  end

  test "rejects blank chat messages" do
    player_id = unique_player("chat-blank")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)

    assert {:error, :empty} = GameLobby.send_chat(player_id, view.game_id, "   ")
    assert GameLobby.snapshot(view.game_id).chat == []
  end

  test "rejects moving from an empty square without changing the board" do
    player_id = unique_player("empty-move")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    before_board = view.game.board

    assert :ok = GameLobby.enqueue(player_id, {4, 4}, {3, 4})

    game = GameLobby.snapshot(view.game_id)
    assert game.board == before_board
    assert hd(game.log) == "Movimiento rechazado: no hay pieza en origen {4, 4}."
  end

  test "rejects moving a piece while it is on cooldown" do
    player_id = unique_player("cooldown-player")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)

    assert :ok = GameLobby.enqueue(player_id, {6, 4}, {5, 4})
    assert :ok = GameLobby.enqueue(player_id, {5, 4}, {4, 4})

    game = GameLobby.snapshot(view.game_id)
    assert hd(game.log) == "Movimiento rechazado: pieza en cooldown."
    assert Enum.at(Enum.at(game.board, 5), 4) == "P"
    assert Enum.at(Enum.at(game.board, 4), 4) == "."
  end
end
