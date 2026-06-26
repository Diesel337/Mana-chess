defmodule ManaChessOnline.GameTick do
  @moduledoc false

  alias ManaChessOnline.GameEngine

  def tick(game, now_ms, tick_ms, default_cooldown_seconds) do
    game
    |> before_bot(now_ms, tick_ms)
    |> after_bot(now_ms, default_cooldown_seconds)
  end

  def before_bot(game, now_ms, tick_ms) do
    game
    |> GameEngine.clear_expired_cooldowns(now_ms)
    |> GameEngine.regen_elixir(tick_ms)
    |> finish_countdown(now_ms)
  end

  def after_bot(game, now_ms, default_cooldown_seconds) do
    game
    |> GameEngine.process_next_action(now_ms, default_cooldown_seconds)
    |> GameEngine.refresh_terminal_status(now_ms)
  end

  def finish_countdown(%{status: {:starting, starts_at}} = game, now_ms) do
    if now_ms >= starts_at do
      start_playing(game)
    else
      game
    end
  end

  def finish_countdown(game, _now_ms), do: game

  def start_when_ready(%{status: {:starting, _starts_at}} = game, seated_players) do
    if seated_players != [] and
         Enum.all?(seated_players, &MapSet.member?(game.start_requests, &1)) do
      start_playing(game)
    else
      game
    end
  end

  def start_when_ready(game, _seated_players), do: game

  def start_playing(game) do
    %{
      game
      | status: :playing,
        queue: [],
        start_requests: MapSet.new(),
        log: ["Partida iniciada. Blancas abren." | game.log]
    }
  end
end
