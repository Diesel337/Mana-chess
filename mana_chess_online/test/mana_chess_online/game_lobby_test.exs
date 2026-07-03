defmodule ManaChessOnline.GameLobbyTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameLobby, GameServer, GameState, GameSupervisor}

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

  defp settings_params(settings) do
    %{
      "max_elixir" => settings.max_elixir,
      "initial_elixir" => settings.initial_elixir,
      "regen_per_second" => settings.regen_per_second,
      "capture_refund_percent" => settings.capture_refund_percent,
      "cooldown_enabled" => settings.cooldown_enabled,
      "cooldown_seconds" => settings.cooldown_seconds,
      "bot_move_seconds" => settings.bot_move_seconds,
      "pawn" => settings.costs.pawn,
      "knight" => settings.costs.knight,
      "bishop" => settings.costs.bishop,
      "rook" => settings.costs.rook,
      "queen" => settings.costs.queen,
      "king" => settings.costs.king
    }
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

  test "reads runtime metrics from registered game servers" do
    player_id = unique_player("metrics-owner")

    on_exit(fn ->
      GameLobby.leave(player_id)
    end)

    {:ok, view} = GameLobby.create_private(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    before = GameLobby.metrics()

    server_game =
      GameServer.update(pid, fn game ->
        %{game | bot_enabled?: true}
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.bot_enabled? == server_game.bot_enabled?

    metrics = GameLobby.metrics()
    assert metrics.bot_game_count == before.bot_game_count + 1
  end

  test "creates private games outside the public lobby and lets spectators watch by link" do
    player_id = unique_player("private-owner")
    on_exit(fn -> GameLobby.leave(player_id) end)

    {:ok, view} = GameLobby.create_private(player_id)

    assert String.starts_with?(view.game_id, "private_")
    assert view.color == :white
    refute Enum.any?(view.lobby, &(&1.id == view.game_id))
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game == lobby_game
    assert server_game.private?
    assert server_game.players.white == player_id
    assert server_game.players.black == nil

    game = GameLobby.snapshot(view.game_id)
    assert game.private?
    assert game.players.white == player_id
    assert game.players.black == nil

    spectator_view = GameLobby.watch(unique_player("spectator"), view.game_id)
    assert spectator_view.game_id == view.game_id
    assert spectator_view.color == nil
    assert spectator_view.game.private?
  end

  test "mirrors lazy private rooms through the registered game server" do
    spectator_id = unique_player("lazy-spectator")
    game_id = "private_lazy_" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    view = GameLobby.watch(spectator_id, game_id)
    assert view.game_id == game_id
    assert view.color == nil
    assert view.game.private?
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game == lobby_game
    assert server_game.players == %{white: nil, black: nil}
    assert server_game.status == :waiting
    assert server_game.log == ["Sala privada creada. Comparte el link para invitar."]
  end

  test "watching a mirrored private room restarts a missing game server" do
    spectator_id = unique_player("restart-private-spectator")
    game_id = "private_restart_" <> Integer.to_string(System.unique_integer([:positive]))

    game =
      GameState.private_game(game_id, GameLobby.global_settings())
      |> Map.put(:players, %{white: "mirror-white", black: nil})
      |> Map.put(:log, ["Mirror conserva sala privada."])

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    GameSupervisor.stop_game(game_id)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.put(state.games, game_id, game)}
    end)

    assert GameSupervisor.lookup_game(game_id) == :error

    view = GameLobby.watch(spectator_id, game_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    server_game = GameServer.snapshot(pid)

    assert view.game.log == ["Mirror conserva sala privada."]
    assert server_game == lobby_game
    assert server_game == game
  end

  test "watching a private room preserves an existing live game server" do
    spectator_id = unique_player("live-private-spectator")
    game_id = "private_live_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.private_game(game_id, GameLobby.global_settings())

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    assert {:ok, pid} = GameSupervisor.upsert_game(game)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | players: %{white: "live-white", black: nil},
            log: ["Servidor privado vivo." | game.log]
        }
      end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    view = GameLobby.watch(spectator_id, game_id)

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    server_game_after_watch = GameServer.snapshot(pid)

    assert view.game_id == game_id
    assert view.game.log == server_game.log
    assert server_game_after_watch == server_game
    assert lobby_game == server_game
  end

  test "reads snapshots from the registered game server" do
    player_id = unique_player("snapshot-server")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{game | log: ["Servidor manda snapshot." | game.log]}
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.log == server_game.log

    snapshot = GameLobby.snapshot(view.game_id)
    assert snapshot.log == server_game.log
  end

  test "reads player views from the registered game server" do
    owner_id = unique_player("view-owner")
    spectator_id = unique_player("view-spectator")

    on_exit(fn ->
      GameLobby.leave(owner_id)
      GameLobby.leave(spectator_id)
    end)

    {:ok, view} = GameLobby.create_private(owner_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{game | log: ["Vista desde servidor." | game.log]}
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.log == server_game.log

    spectator_view = GameLobby.watch(spectator_id, view.game_id)
    assert spectator_view.game.log == server_game.log
  end

  test "reads public lobby views from registered game servers" do
    game_id = "live_lobby_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, GameLobby.global_settings())

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.put(state.games, game_id, game)}
    end)

    assert {:ok, pid} = GameSupervisor.upsert_game(game)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | players: %{white: "live-white", black: "live-black"},
            status: :ready
        }
      end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.put(state.games, game_id, game)}
    end)

    lobby_entry = Enum.find(GameLobby.lobby(), &(&1.id == game_id))

    assert lobby_entry.status == server_game.status
    assert lobby_entry.players == server_game.players
  end

  test "reads public lobby views from registered game servers missing from the mirror" do
    game_id = "live_only_lobby_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, GameLobby.global_settings())

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    assert {:ok, pid} = GameSupervisor.upsert_game(game)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | players: %{white: "live-only-white", black: "live-only-black"},
            status: :ready
        }
      end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    lobby_entry = Enum.find(GameLobby.lobby(), &(&1.id == game_id))

    assert lobby_entry.status == server_game.status
    assert lobby_entry.players == server_game.players
  end

  test "sits anywhere in public game servers missing from the mirror" do
    player_id = unique_player("live-anywhere-player")
    game_id = "aaa_live_anywhere_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, GameLobby.global_settings())

    on_exit(fn ->
      GameLobby.leave(player_id)
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{
          state
          | games: Map.delete(state.games, game_id),
            players: Map.delete(state.players, player_id)
        }
      end)
    end)

    assert {:ok, pid} = GameSupervisor.upsert_game(game)

    GameServer.update(pid, fn game ->
      %{
        game
        | players: %{white: "live-anywhere-white", black: nil},
          status: :waiting
      }
    end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    view = GameLobby.sit_anywhere(player_id)
    lobby_game = :sys.get_state(GameLobby).games[game_id]
    server_game = GameServer.snapshot(pid)

    assert view.game_id == game_id
    assert view.color == :black
    assert lobby_game == server_game
    assert server_game.players == %{white: "live-anywhere-white", black: player_id}
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

  test "mirrors private seats through the registered game server" do
    white_id = unique_player("mirror-private-white")
    black_id = unique_player("mirror-private-black")

    on_exit(fn ->
      GameLobby.leave(white_id)
      GameLobby.leave(black_id)
    end)

    {:ok, white_view} = GameLobby.create_private(white_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(white_view.game_id)
    assert GameServer.snapshot(pid).players.white == white_id

    black_view = GameLobby.sit(black_id, white_view.game_id, :black)
    lobby_game = :sys.get_state(GameLobby).games[white_view.game_id]
    server_game = GameServer.snapshot(pid)

    assert black_view.color == :black
    assert server_game.players == lobby_game.players
    assert server_game.players == %{white: white_id, black: black_id}
    assert server_game.status == :ready
    assert server_game.status == lobby_game.status
    assert server_game.log == lobby_game.log
  end

  test "drops empty private rooms after the last player leaves" do
    white_id = unique_player("drop-private-white")
    black_id = unique_player("drop-private-black")

    {:ok, white_view} = GameLobby.create_private(white_id)
    game_id = white_view.game_id
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    black_view = GameLobby.sit(black_id, game_id, :black)
    assert black_view.game.status == :ready

    assert :ok = GameLobby.leave(black_id)
    assert {:ok, ^pid} = GameSupervisor.lookup_game(game_id)
    assert GameLobby.snapshot(game_id).players == %{white: white_id, black: nil}

    assert :ok = GameLobby.leave(white_id)

    state = :sys.get_state(GameLobby)

    refute Map.has_key?(state.games, game_id)
    refute Map.has_key?(state.players, white_id)
    refute Map.has_key?(state.players, black_id)
    assert GameSupervisor.lookup_game(game_id) == :error
    assert GameLobby.snapshot(game_id) == nil
  end

  test "drops empty private rooms from registered game server when the lobby mirror is missing" do
    white_id = unique_player("drop-live-private-white")
    black_id = unique_player("drop-live-private-black")

    {:ok, white_view} = GameLobby.create_private(white_id)
    game_id = white_view.game_id

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{
          state
          | games: Map.delete(state.games, game_id),
            players: Map.drop(state.players, [white_id, black_id])
        }
      end)
    end)

    black_view = GameLobby.sit(black_id, game_id, :black)
    assert black_view.game.status == :ready
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    assert :ok = GameLobby.leave(black_id)
    assert {:ok, ^pid} = GameSupervisor.lookup_game(game_id)
    assert GameServer.snapshot(pid).players == %{white: white_id, black: nil}

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    assert :ok = GameLobby.leave(white_id)

    state = :sys.get_state(GameLobby)

    refute Map.has_key?(state.games, game_id)
    refute Map.has_key?(state.players, white_id)
    refute Map.has_key?(state.players, black_id)
    assert GameSupervisor.lookup_game(game_id) == :error
    assert GameLobby.snapshot(game_id) == nil
  end

  test "mirrors public seats when a player leaves" do
    player_id = unique_player("mirror-public-leave")
    view = GameLobby.sit(player_id, "game_1", :white)

    assert view.game_id == "game_1"
    assert {:ok, pid} = GameSupervisor.lookup_game("game_1")
    assert GameServer.snapshot(pid).players.white == player_id

    assert :ok = GameLobby.leave(player_id)

    lobby_game = :sys.get_state(GameLobby).games["game_1"]
    server_game = GameServer.snapshot(pid)

    assert server_game == lobby_game
    assert server_game.players.white == nil
    assert server_game.status == :waiting
    assert server_game.queue == []
    assert server_game.reset_requests == MapSet.new()
    assert hd(server_game.log) == "Blancas dejo la partida."
  end

  test "mirrors cleared public rooms through the registered game server" do
    white_id = unique_player("clear-white")
    black_id = unique_player("clear-black")
    game_id = "game_2"

    on_exit(fn -> GameLobby.clear_room(game_id) end)

    GameLobby.clear_room(game_id)
    white_view = GameLobby.sit(white_id, game_id, :white)
    black_view = GameLobby.sit(black_id, game_id, :black)
    assert white_view.game_id == game_id
    assert black_view.game.status == :ready
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    assert :ok = GameLobby.clear_room(game_id)

    state = :sys.get_state(GameLobby)
    lobby_game = state.games[game_id]
    server_game = GameServer.snapshot(pid)

    refute Map.has_key?(state.players, white_id)
    refute Map.has_key?(state.players, black_id)
    assert server_game == lobby_game
    assert server_game.status == :waiting
    assert server_game.players == %{white: nil, black: nil}
    assert server_game.queue == []
    assert server_game.reset_requests == MapSet.new()
    assert server_game.log == ["Esperando jugadores..."]
  end

  test "clears public rooms from registered game server when the lobby mirror is missing" do
    white_id = unique_player("clear-live-white")
    black_id = unique_player("clear-live-black")
    game_id = "game_3"

    on_exit(fn -> GameLobby.clear_room(game_id) end)

    GameLobby.clear_room(game_id)
    assert %{game_id: ^game_id} = GameLobby.sit(white_id, game_id, :white)
    assert %{game: %{status: :ready}} = GameLobby.sit(black_id, game_id, :black)
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    GameServer.update(pid, fn game ->
      %{game | log: ["Servidor vivo antes de limpiar." | game.log]}
    end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    assert :ok = GameLobby.clear_room(game_id)

    state = :sys.get_state(GameLobby)
    lobby_game = state.games[game_id]
    server_game = GameServer.snapshot(pid)

    refute Map.has_key?(state.players, white_id)
    refute Map.has_key?(state.players, black_id)
    assert server_game == lobby_game
    assert server_game.status == :waiting
    assert server_game.players == %{white: nil, black: nil}
    assert server_game.log == ["Esperando jugadores..."]
  end

  test "clears private rooms from registered game server without exposing them in lobby" do
    white_id = unique_player("clear-live-private-white")
    black_id = unique_player("clear-live-private-black")

    {:ok, white_view} = GameLobby.create_private(white_id)
    game_id = white_view.game_id

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{
          state
          | games: Map.delete(state.games, game_id),
            players: Map.drop(state.players, [white_id, black_id])
        }
      end)
    end)

    assert %{game: %{status: :ready}} = GameLobby.sit(black_id, game_id, :black)
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    assert :ok = GameLobby.clear_room(game_id)

    state = :sys.get_state(GameLobby)
    lobby_game = state.games[game_id]
    server_game = GameServer.snapshot(pid)

    refute Map.has_key?(state.players, white_id)
    refute Map.has_key?(state.players, black_id)
    assert server_game == lobby_game
    assert server_game.private?
    assert server_game.status == :waiting
    assert server_game.players == %{white: nil, black: nil}
    assert server_game.log == ["Sala privada creada. Comparte el link para invitar."]
    refute Enum.any?(GameLobby.lobby(), &(&1.id == game_id))
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
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game == lobby_game
    assert server_game.id == view.game_id
    assert server_game.players.white == player_id
    assert server_game.players.black == player_id

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

  test "practice side toggles keep the live bot disabled state" do
    player_id = unique_player("side-toggle-bot-disabled")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    assert :ok = GameLobby.send_chat(player_id, view.game_id, "bot apagado sigue apagado")
    view = GameLobby.toggle_practice_bot(player_id)
    refute view.game.bot_enabled?

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, view.game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, view.game_id)

    view = GameLobby.toggle_practice_side(player_id)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    refute server_game.bot_enabled?
    assert server_game.bot_ready_at == nil
    assert server_game.bot_color == :white
    assert server_game.bot_enabled? == lobby_game.bot_enabled?
    assert server_game.bot_ready_at == lobby_game.bot_ready_at
    assert server_game.chat == lobby_game.chat
    assert hd(server_game.chat).text == "bot apagado sigue apagado"
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

  test "mirrors global settings updates for waiting rooms through the registered game server" do
    original_settings = GameLobby.global_settings()
    on_exit(fn -> GameLobby.update_global_settings(settings_params(original_settings)) end)

    {game_id, _game} =
      :sys.get_state(GameLobby).games
      |> Enum.find(fn {_game_id, game} ->
        game.status == :waiting and game.players.white == nil
      end)

    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    settings =
      GameLobby.update_global_settings(%{
        "max_elixir" => "13",
        "initial_elixir" => "5",
        "regen_per_second" => "1.75",
        "cooldown_seconds" => "2.5"
      })

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.settings == settings
    assert server_game.settings == lobby_game.settings
    assert server_game.elixir == %{white: 5.0, black: 5.0}
    assert server_game.elixir == lobby_game.elixir
    assert server_game.cooldowns == %{}
    assert server_game.cooldowns == lobby_game.cooldowns
  end

  test "global settings skip rooms that are occupied in the registered game server" do
    original_settings = GameLobby.global_settings()
    game_id = "live_global_skip_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, original_settings)

    on_exit(fn ->
      GameLobby.update_global_settings(settings_params(original_settings))
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.put(state.games, game_id, game)}
    end)

    assert {:ok, pid} = GameSupervisor.upsert_game(game)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | players: %{white: "live-white", black: nil},
            status: :waiting,
            log: ["Servidor ocupado." | game.log]
        }
      end)

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    assert lobby_game.players.white == nil
    assert server_game.players.white == "live-white"

    settings =
      GameLobby.update_global_settings(%{
        "max_elixir" => "14",
        "initial_elixir" => "6",
        "regen_per_second" => "1.25"
      })

    server_game = GameServer.snapshot(pid)
    lobby_game = :sys.get_state(GameLobby).games[game_id]

    refute server_game.settings == settings
    assert server_game.settings == original_settings
    assert server_game.players.white == "live-white"
    assert "Servidor ocupado." in server_game.log
    assert lobby_game.settings == server_game.settings
    assert lobby_game.players == server_game.players
  end

  test "mirrors global settings applied to practice through the registered game server" do
    player_id = unique_player("mirror-global-practice-settings")
    original_settings = GameLobby.global_settings()

    on_exit(fn ->
      :sys.replace_state(GameLobby, &%{&1 | global_settings: original_settings})
      GameLobby.leave(player_id)
    end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)
    settings = %{view.game.settings | max_elixir: 7.0, regen_per_second: 2.5}

    GameServer.update(pid, fn game ->
      %{
        game
        | elixir: %{white: 10.0, black: 4.0},
          cooldowns: %{{6, 4} => 99_999},
          log: ["Antes de admin." | game.log]
      }
    end)

    :sys.replace_state(GameLobby, fn state ->
      Map.put(state, :global_settings, settings)
    end)

    assert :ok = GameLobby.apply_global_settings_to_practice(player_id)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game.settings == settings
    assert server_game.settings == lobby_game.settings
    assert server_game.elixir == %{white: 7.0, black: 4.0}
    assert server_game.elixir == lobby_game.elixir
    assert server_game.cooldowns == %{}
    assert server_game.log == lobby_game.log
    assert hd(server_game.log) == "Configuracion admin aplicada a la practica."
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

  test "mirrors agreed resets through the registered game server" do
    white_id = unique_player("reset-agree-white")
    black_id = unique_player("reset-agree-black")

    on_exit(fn ->
      GameLobby.leave(white_id)
      GameLobby.leave(black_id)
    end)

    {:ok, white_view} = GameLobby.create_private(white_id)
    black_view = GameLobby.sit(black_id, white_view.game_id, :black)
    assert black_view.game.status == :ready
    assert {:ok, pid} = GameSupervisor.lookup_game(white_view.game_id)
    assert :ok = GameLobby.send_chat(white_id, white_view.game_id, "reinicio con chat")

    assert :ok = GameLobby.reset(white_id)
    assert :ok = GameLobby.reset(black_id)

    lobby_game = :sys.get_state(GameLobby).games[white_view.game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game == lobby_game
    assert server_game.status == :ready
    assert server_game.players == %{white: white_id, black: black_id}
    assert server_game.reset_requests == MapSet.new()
    assert server_game.queue == []
    assert hd(server_game.log) == "Partida reiniciada por acuerdo."
    assert [%{text: "reinicio con chat"} | _rest] = server_game.chat
  end

  test "agreed resets use the registered game server when the lobby mirror is missing" do
    white_id = unique_player("reset-live-white")
    black_id = unique_player("reset-live-black")

    on_exit(fn ->
      GameLobby.leave(white_id)
      GameLobby.leave(black_id)
    end)

    {:ok, white_view} = GameLobby.create_private(white_id)
    black_view = GameLobby.sit(black_id, white_view.game_id, :black)
    game_id = white_view.game_id

    assert black_view.game.status == :ready
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    assert :ok = GameLobby.reset(white_id)

    live_chat = %{
      player_id: white_id,
      name: "Jugador LIVE",
      role: "Blancas",
      sent_at: System.system_time(:millisecond),
      text: "chat vivo entre votos"
    }

    GameServer.update(pid, fn game ->
      %{game | chat: [live_chat | game.chat]}
    end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    assert :ok = GameLobby.reset(black_id)

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    server_game = GameServer.snapshot(pid)

    assert server_game == lobby_game
    assert server_game.status == :ready
    assert server_game.players == %{white: white_id, black: black_id}
    assert server_game.reset_requests == MapSet.new()
    assert hd(server_game.log) == "Partida reiniciada por acuerdo."
    assert [%{text: "chat vivo entre votos"} | _rest] = server_game.chat
  end

  test "mirrors promotions through the registered game server" do
    player_id = unique_player("promote-player")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | board: promotion_board(),
            status: :promotion,
            promotion_pending: %{player_id: player_id, color: :white, at: {0, 0}},
            log: ["Promocion pendiente." | game.log]
        }
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.promotion_pending == server_game.promotion_pending

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

  test "lobby broadcasts do not overwrite live game server state" do
    player_id = unique_player("broadcast-preserve")
    other_id = unique_player("broadcast-other")

    on_exit(fn ->
      GameLobby.leave(player_id)
      GameLobby.leave(other_id)
    end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | log: ["Broadcast no pisa estado vivo." | game.log]
        }
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.log == server_game.log

    GameLobby.start_practice(other_id)

    server_game = GameServer.snapshot(pid)

    assert "Broadcast no pisa estado vivo." in server_game.log
  end

  test "lobby ticks do not overwrite live game server state" do
    player_id = unique_player("tick-preserve")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{game | log: ["Tick conserva estado vivo." | game.log]}
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.log == server_game.log

    send(Process.whereis(GameLobby), :tick)
    :sys.get_state(GameLobby)

    server_game = GameServer.snapshot(pid)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]

    assert "Tick conserva estado vivo." in server_game.log
    assert lobby_game.log == server_game.log
  end

  test "lobby ticks restore registered game servers missing from the mirror" do
    game_id = "live_tick_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, GameLobby.global_settings())

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{state | games: Map.delete(state.games, game_id)}
      end)
    end)

    assert {:ok, pid} = GameSupervisor.upsert_game(game)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | players: %{white: "live-tick-white", black: "live-tick-black"},
            status: :ready,
            log: ["Servidor vivo antes del tick." | game.log]
        }
      end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    send(Process.whereis(GameLobby), :tick)
    state = :sys.get_state(GameLobby)

    lobby_game = state.games[game_id]
    server_game_after_tick = GameServer.snapshot(pid)

    assert lobby_game == server_game_after_tick
    assert lobby_game.players == server_game.players
    assert "Servidor vivo antes del tick." in lobby_game.log
  end

  test "starts games from the registered game server ready state" do
    white_id = unique_player("live-start-white")
    black_id = unique_player("live-start-black")

    {:ok, view} = GameLobby.create_private(white_id)
    game_id = view.game_id

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{
          state
          | games: Map.delete(state.games, game_id),
            players: Map.drop(state.players, [white_id, black_id])
        }
      end)
    end)

    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    GameServer.update(pid, fn game ->
      %{
        game
        | players: %{white: white_id, black: black_id},
          status: :ready,
          log: ["Servidor marco listo." | game.log]
      }
    end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, game_id)

    assert :ok = GameLobby.start_game(white_id)

    server_game = GameServer.snapshot(pid)
    lobby_game = :sys.get_state(GameLobby).games[game_id]

    assert match?({:starting, _starts_at}, server_game.status)
    assert server_game.status == lobby_game.status
    assert "Servidor marco listo." in server_game.log
  end

  test "does not update settings when the registered game server is already playing" do
    player_id = unique_player("live-settings-player")

    {:ok, view} = GameLobby.create_private(player_id)
    game_id = view.game_id

    on_exit(fn ->
      GameSupervisor.stop_game(game_id)

      :sys.replace_state(GameLobby, fn state ->
        %{
          state
          | games: Map.delete(state.games, game_id),
            players: Map.delete(state.players, player_id)
        }
      end)
    end)

    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | status: :playing,
            first_move_pending: :white,
            log: ["Servidor ya esta jugando." | game.log]
        }
      end)

    lobby_game = :sys.get_state(GameLobby).games[game_id]
    assert lobby_game.status == :waiting
    assert server_game.status == :playing

    assert :ok =
             GameLobby.update_settings(player_id, %{
               "max_elixir" => "18",
               "initial_elixir" => "9"
             })

    server_game = GameServer.snapshot(pid)

    assert server_game.settings == view.game.settings
    assert server_game.status == :playing
    assert "Servidor ya esta jugando." in server_game.log
    refute hd(server_game.log) == "Blancas ajustaron la configuracion."
    assert GameLobby.snapshot(game_id).status == :playing
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

  test "enqueues registered game server actions without overwriting live state" do
    player_id = unique_player("move-preserve")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{game | log: ["Movimiento conserva estado vivo." | game.log]}
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.log == server_game.log

    assert :ok = GameLobby.enqueue(player_id, {6, 4}, {4, 4})

    server_game = GameServer.snapshot(pid)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]

    assert "Movimiento conserva estado vivo." in server_game.log
    assert String.starts_with?(hd(server_game.log), "Blancas movio peon")
    assert lobby_game.log == server_game.log
    assert lobby_game.board == server_game.board
  end

  test "validates player moves against the registered game server state" do
    player_id = unique_player("move-live-validation")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    GameServer.enqueue(
      pid,
      %{player_id: player_id, color: :white, from: {6, 4}, to: {4, 4}},
      10_000
    )

    server_game =
      GameServer.update(pid, fn game ->
        %{
          game
          | bot_enabled?: false,
            bot_ready_at: nil,
            cooldowns: %{},
            log: ["Servidor vivo adelanto el tablero." | game.log]
        }
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.board == server_game.board
    assert lobby_game.board |> Enum.at(4) |> Enum.at(4) == "."
    assert server_game.board |> Enum.at(4) |> Enum.at(4) == "P"

    assert :ok = GameLobby.enqueue(player_id, {4, 4}, {3, 4})

    server_game = GameServer.snapshot(pid)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]

    assert server_game.board |> Enum.at(3) |> Enum.at(4) == "P"
    assert server_game.board |> Enum.at(4) |> Enum.at(4) == "."
    assert String.starts_with?(hd(server_game.log), "Blancas movio peon")
    assert "Servidor vivo adelanto el tablero." in server_game.log
    assert lobby_game.board == server_game.board
    assert lobby_game.log == server_game.log
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

  test "rejected moves use the registered game server when the lobby mirror is missing" do
    player_id = unique_player("rejected-live-move")
    on_exit(fn -> GameLobby.leave(player_id) end)

    view = GameLobby.start_practice(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{game | log: ["Servidor vivo antes del rechazo." | game.log]}
      end)

    :sys.replace_state(GameLobby, fn state ->
      %{state | games: Map.delete(state.games, view.game_id)}
    end)

    refute Map.has_key?(:sys.get_state(GameLobby).games, view.game_id)

    assert :ok = GameLobby.enqueue(player_id, {4, 4}, {3, 4})

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    server_game_after_reject = GameServer.snapshot(pid)

    assert hd(server_game_after_reject.log) ==
             "Movimiento rechazado: no hay pieza en origen {4, 4}."

    assert "Servidor vivo antes del rechazo." in server_game_after_reject.log
    assert lobby_game == server_game_after_reject
    assert server_game_after_reject.board == server_game.board
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

  test "updates registered game servers without overwriting live state" do
    player_id = unique_player("chat-preserve")
    on_exit(fn -> GameLobby.leave(player_id) end)

    {:ok, view} = GameLobby.create_private(player_id)
    assert {:ok, pid} = GameSupervisor.lookup_game(view.game_id)

    server_game =
      GameServer.update(pid, fn game ->
        %{game | log: ["Estado vivo preservado." | game.log]}
      end)

    lobby_game = :sys.get_state(GameLobby).games[view.game_id]
    refute lobby_game.log == server_game.log

    assert :ok = GameLobby.send_chat(player_id, view.game_id, "no pisar server")

    server_game = GameServer.snapshot(pid)
    lobby_game = :sys.get_state(GameLobby).games[view.game_id]

    assert "Estado vivo preservado." in server_game.log
    assert hd(server_game.chat).text == "no pisar server"
    assert lobby_game.log == server_game.log
    assert lobby_game.chat == server_game.chat
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
