defmodule ManaChessOnline.GameSettingsTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.GameSettings

  test "sanitizes numeric and boolean settings" do
    settings =
      GameSettings.sanitize(
        %{
          "max_elixir" => "12.345",
          "initial_elixir" => "99",
          "regen_per_second" => "-4",
          "capture_refund_percent" => "150",
          "cooldown_enabled" => "false",
          "cooldown_seconds" => "2.255",
          "bot_move_seconds" => "0.1",
          "pawn" => "-3",
          "queen" => "7.777"
        },
        GameSettings.default_settings()
      )

    assert settings.settings_version == 2
    assert settings.max_elixir == 12.35
    assert settings.initial_elixir == 12.35
    assert settings.regen_per_second == 0.0
    assert settings.capture_refund_percent == 100.0
    assert settings.cooldown_enabled == false
    assert settings.cooldown_seconds == 2.25
    assert settings.bot_move_seconds == 0.25
    assert settings.costs.pawn == 0.0
    assert settings.costs.queen == 7.78
  end

  test "loads old persisted settings and migrates full initial elixir to half" do
    previous_path = System.get_env("MANA_CHESS_SETTINGS_PATH")

    path =
      Path.join(
        System.tmp_dir!(),
        "mana_chess_settings_test_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn ->
      if previous_path,
        do: System.put_env("MANA_CHESS_SETTINGS_PATH", previous_path),
        else: System.delete_env("MANA_CHESS_SETTINGS_PATH")

      File.rm(path)
    end)

    System.put_env("MANA_CHESS_SETTINGS_PATH", path)

    File.write!(path, Jason.encode!(%{"max_elixir" => 8, "initial_elixir" => 8}))

    settings = GameSettings.load_global()

    assert settings.settings_version == 2
    assert settings.max_elixir == 8.0
    assert settings.initial_elixir == 4.0
    assert settings.costs == GameSettings.default_settings().costs

    assert {:ok, persisted} = File.read(path)
    assert {:ok, %{"settings_version" => 2}} = Jason.decode(persisted)
  end

  test "builds and clamps elixir from settings" do
    settings = %{GameSettings.default_settings() | max_elixir: 8.0, initial_elixir: 4.0}

    assert GameSettings.full_elixir(settings) == %{white: 4.0, black: 4.0}

    assert GameSettings.clamp_elixir(%{white: 12.0, black: 3.0}, settings) == %{
             white: 8.0,
             black: 3.0
           }
  end

  test "loads global settings from the optional persistence store" do
    original_config = Application.get_env(:mana_chess_online, :persistence)
    original_settings = Application.get_env(:mana_chess_online, :persistence_test_settings)
    original_path = System.get_env("MANA_CHESS_SETTINGS_PATH")
    path = Path.join(System.tmp_dir!(), "mana_chess_db_settings_#{System.unique_integer()}.json")

    on_exit(fn ->
      restore_app_env(:persistence, original_config)
      restore_app_env(:persistence_test_settings, original_settings)

      if original_path,
        do: System.put_env("MANA_CHESS_SETTINGS_PATH", original_path),
        else: System.delete_env("MANA_CHESS_SETTINGS_PATH")

      File.rm(path)
    end)

    Application.put_env(:mana_chess_online, :persistence,
      enabled: true,
      store: ManaChessOnline.PersistenceTestStore,
      writer: ManaChessOnline.PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_settings, %{
      "global_game_settings" => %{
        "settings_version" => 2,
        "max_elixir" => 14,
        "initial_elixir" => 6,
        "queen" => 8
      }
    })

    System.put_env("MANA_CHESS_SETTINGS_PATH", path)

    settings = GameSettings.load_global()
    assert settings.max_elixir == 14.0
    assert settings.initial_elixir == 6.0
    assert settings.costs.queen == 8.0
    assert File.exists?(path)
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_app_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
