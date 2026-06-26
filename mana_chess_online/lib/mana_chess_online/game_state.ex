defmodule ManaChessOnline.GameState do
  @moduledoc false

  alias ManaChessOnline.GameRules

  def new_game(id, settings) do
    %{
      id: id,
      board: GameRules.initial_board(),
      players: %{white: nil, black: nil},
      practice?: false,
      private?: false,
      settings: settings,
      elixir: full_elixir(settings),
      castling_rights: %{
        {:white, :king} => true,
        {:white, :queen} => true,
        {:black, :king} => true,
        {:black, :queen} => true
      },
      cooldowns: %{},
      bot_enabled?: false,
      bot_ready_at: nil,
      promotion_pending: nil,
      finished_at: nil,
      first_move_pending: :white,
      reset_requests: MapSet.new(),
      start_requests: MapSet.new(),
      queue: [],
      status: :waiting,
      chat: [],
      log: ["Esperando jugadores..."]
    }
  end

  def practice_game(id, player_id, settings, now_ms, bot_move_ms) do
    %{
      new_game(id, settings)
      | players: %{white: player_id, black: player_id},
        practice?: true,
        bot_enabled?: true,
        bot_ready_at: now_ms + bot_move_ms,
        status: :playing,
        log: ["BOT encendido.", "Practica iniciada. Blancas abren."]
    }
  end

  def private_game(id, settings) do
    %{
      new_game(id, settings)
      | private?: true,
        log: ["Sala privada creada. Comparte el link para invitar."]
    }
  end

  def public_game(nil, _now_ms, _default_cooldown_seconds), do: nil

  def public_game(game, now_ms, default_cooldown_seconds) do
    %{
      id: game.id,
      board: game.board,
      players: game.players,
      practice?: game.practice?,
      private?: Map.get(game, :private?, false),
      elixir: game.elixir,
      settings: game.settings,
      bot_enabled?: game.bot_enabled?,
      castling_rights: game.castling_rights,
      cooldowns: public_cooldowns(game, now_ms, default_cooldown_seconds),
      queue: game.queue,
      status: game.status,
      countdown_seconds: countdown_seconds(game.status, now_ms),
      first_move_pending: game.first_move_pending,
      reset_requests: MapSet.to_list(game.reset_requests),
      start_requests: MapSet.to_list(game.start_requests),
      checked_colors: GameRules.checked_colors(game.board),
      promotion_pending: game.promotion_pending,
      finished_at: game.finished_at,
      chat: Map.get(game, :chat, []),
      log: Enum.take(game.log, 8)
    }
  end

  def public_lobby(%{games: games}, now_ms) do
    games
    |> Enum.reject(fn {_game_id, game} -> game.practice? or Map.get(game, :private?, false) end)
    |> Enum.sort_by(fn {game_id, _game} -> game_id end)
    |> Enum.map(fn {_game_id, game} ->
      %{
        id: game.id,
        players: game.players,
        status: game.status,
        countdown_seconds: countdown_seconds(game.status, now_ms)
      }
    end)
  end

  def full_elixir(settings) do
    initial_elixir = min(settings.initial_elixir, settings.max_elixir)
    %{white: initial_elixir, black: initial_elixir}
  end

  def piece_cooldown(settings, default_cooldown_seconds) do
    Map.get(settings, :cooldown_seconds, default_cooldown_seconds)
  end

  def countdown_seconds({:starting, starts_at}, now_ms) do
    remaining = starts_at - now_ms
    max(0, ceil(remaining / 1000))
  end

  def countdown_seconds(_status, _now_ms), do: nil

  def public_cooldowns(game, now_ms, default_cooldown_seconds) do
    game.cooldowns
    |> Enum.flat_map(fn {square, ready_at} ->
      remaining = ready_at - now_ms
      piece = GameRules.at(game.board, elem(square, 0), elem(square, 1))

      if remaining > 0 and piece != "." do
        total = round(piece_cooldown(game.settings, default_cooldown_seconds) * 1000)

        [
          %{
            at: square,
            seconds: max(1, ceil(remaining / 1000)),
            remaining_ms: remaining,
            total_ms: total
          }
        ]
      else
        []
      end
    end)
  end
end
