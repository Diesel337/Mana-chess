defmodule ManaChessOnline.GameSettings do
  @moduledoc false

  @bot_move_seconds 1.2
  @settings_file "mana_chess_settings.json"
  @settings_version 2
  @default_settings %{
    settings_version: @settings_version,
    max_elixir: 10.0,
    initial_elixir: 5.0,
    regen_per_second: 1.0,
    capture_refund_percent: 40,
    cooldown_enabled: true,
    cooldown_seconds: 1.0,
    bot_move_seconds: @bot_move_seconds,
    costs: %{
      pawn: 1.0,
      knight: 3.0,
      bishop: 3.0,
      rook: 4.0,
      queen: 6.0,
      king: 3.0
    }
  }

  def default_settings, do: @default_settings
  def default_cooldown_seconds, do: @default_settings.cooldown_seconds

  def sanitize(params, current) do
    current_costs = Map.get(current, :costs, @default_settings.costs)
    max_elixir = number_param(params, "max_elixir", Map.get(current, :max_elixir, 10.0), 1, 99)

    %{
      settings_version: @settings_version,
      max_elixir: max_elixir,
      initial_elixir:
        number_param(
          params,
          "initial_elixir",
          Map.get(current, :initial_elixir, max_elixir),
          0,
          max_elixir
        ),
      regen_per_second:
        number_param(params, "regen_per_second", Map.get(current, :regen_per_second, 1.0), 0, 20),
      capture_refund_percent:
        number_param(
          params,
          "capture_refund_percent",
          Map.get(current, :capture_refund_percent, 40),
          0,
          100
        ),
      cooldown_enabled:
        bool_param(params, "cooldown_enabled", Map.get(current, :cooldown_enabled, true)),
      cooldown_seconds:
        number_param(params, "cooldown_seconds", Map.get(current, :cooldown_seconds, 1.0), 0, 60),
      bot_move_seconds:
        number_param(
          params,
          "bot_move_seconds",
          Map.get(current, :bot_move_seconds, @bot_move_seconds),
          0.25,
          30
        ),
      costs: %{
        pawn: number_param(params, "pawn", Map.get(current_costs, :pawn, 1.0), 0, 99),
        knight: number_param(params, "knight", Map.get(current_costs, :knight, 3.0), 0, 99),
        bishop: number_param(params, "bishop", Map.get(current_costs, :bishop, 3.0), 0, 99),
        rook: number_param(params, "rook", Map.get(current_costs, :rook, 4.0), 0, 99),
        queen: number_param(params, "queen", Map.get(current_costs, :queen, 6.0), 0, 99),
        king: number_param(params, "king", Map.get(current_costs, :king, 3.0), 0, 99)
      }
    }
  end

  def load_global do
    path = settings_path()

    with {:ok, json} <- File.read(path),
         {:ok, params} <- Jason.decode(json) do
      settings =
        params
        |> migrate_params()
        |> sanitize(@default_settings)

      persist_global(settings)
      settings
    else
      _ -> @default_settings
    end
  end

  def persist_global(settings) do
    path = settings_path()

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(settings),
         :ok <- File.write(path, json) do
      :ok
    else
      _ -> :ok
    end
  end

  defp bool_param(params, key, fallback) do
    case Map.get(params, key) do
      values when is_list(values) -> bool_param(%{key => List.last(values)}, key, fallback)
      "true" -> true
      "on" -> true
      true -> true
      "false" -> false
      false -> false
      nil -> fallback
      _ -> fallback
    end
  end

  defp number_param(params, key, fallback, min_value, max_value) do
    params
    |> Map.get(key, fallback)
    |> parse_number(fallback)
    |> max(min_value)
    |> min(max_value)
    |> Kernel.*(1.0)
    |> Float.round(2)
  end

  defp parse_number(value, fallback) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> fallback
    end
  end

  defp parse_number(value, _fallback) when is_integer(value), do: value / 1
  defp parse_number(value, _fallback) when is_float(value), do: value
  defp parse_number(_value, fallback), do: fallback

  defp migrate_params(%{"settings_version" => version} = params)
       when is_number(version) and version >= @settings_version, do: params

  defp migrate_params(params) do
    max_elixir = parse_number(Map.get(params, "max_elixir"), @default_settings.max_elixir)

    initial_elixir =
      parse_number(Map.get(params, "initial_elixir"), @default_settings.initial_elixir)

    params
    |> Map.put("settings_version", @settings_version)
    |> maybe_start_at_half_elixir(max_elixir, initial_elixir)
  end

  defp maybe_start_at_half_elixir(params, max_elixir, initial_elixir)
       when initial_elixir >= max_elixir do
    Map.put(params, "initial_elixir", max_elixir / 2)
  end

  defp maybe_start_at_half_elixir(params, _max_elixir, _initial_elixir), do: params

  defp settings_path do
    System.get_env("MANA_CHESS_SETTINGS_PATH") ||
      Path.join(System.get_env("RAILWAY_VOLUME_MOUNT_PATH") || System.tmp_dir!(), @settings_file)
  end
end
