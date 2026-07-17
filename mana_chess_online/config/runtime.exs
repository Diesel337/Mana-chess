import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/mana_chess_online start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :mana_chess_online, ManaChessOnlineWeb.Endpoint, server: true
end

config :mana_chess_online, ManaChessOnlineWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :mana_chess_online, :launch_access,
  mode: System.get_env("MANA_CHESS_LAUNCH_ACCESS", "open"),
  qa_bypass_key: System.get_env("MANA_CHESS_QA_BYPASS_KEY", "")

config :mana_chess_online,
       :leaderboard_alias_secret,
       System.get_env("MANA_CHESS_LEADERBOARD_ALIAS_SECRET") ||
         System.get_env("SECRET_KEY_BASE") ||
         "mana-chess-local-leaderboard-v1"

config :mana_chess_online, :steam_auth,
  app_id: System.get_env("MANA_CHESS_STEAM_APP_ID", ""),
  publisher_key: System.get_env("MANA_CHESS_STEAM_WEB_API_PUBLISHER_KEY", ""),
  ticket_identity: System.get_env("MANA_CHESS_STEAM_TICKET_IDENTITY", "mana-chess-desktop-v1"),
  session_ttl_seconds: System.get_env("MANA_CHESS_STEAM_SESSION_TTL_SECONDS", "86400"),
  client: ManaChessOnline.SteamWebApiClient

positive_integer = fn name, default, maximum ->
  case System.get_env(name, "") |> String.trim() do
    "" ->
      default

    value ->
      case Integer.parse(value) do
        {integer, ""} when integer > 0 -> min(integer, maximum)
        _error -> raise "invalid positive integer for #{name}: #{inspect(value)}"
      end
  end
end

auto_tick =
  case System.get_env("MANA_CHESS_GAME_AUTO_TICK", "true")
       |> String.trim()
       |> String.downcase() do
    value when value in ["1", "true", "yes", "on"] -> true
    value when value in ["0", "false", "no", "off"] -> false
    value -> raise "invalid MANA_CHESS_GAME_AUTO_TICK value: #{inspect(value)}"
  end

config :mana_chess_online, :game_runtime,
  tick_ms: positive_integer.("MANA_CHESS_GAME_TICK_MS", 250, 5_000),
  auto_tick: auto_tick,
  max_dynamic_games: positive_integer.("MANA_CHESS_MAX_DYNAMIC_GAMES", 250, 5_000),
  dynamic_idle_ttl_ms:
    positive_integer.("MANA_CHESS_DYNAMIC_IDLE_TTL_SECONDS", 900, 604_800) * 1_000,
  lifecycle_interval_ms:
    positive_integer.("MANA_CHESS_LIFECYCLE_INTERVAL_SECONDS", 5, 300) * 1_000,
  heartbeat_interval_ms:
    positive_integer.("MANA_CHESS_HEARTBEAT_INTERVAL_SECONDS", 30, 300) * 1_000

database_url = System.get_env("DATABASE_URL", "") |> String.trim()

persistence_enabled =
  case System.get_env("MANA_CHESS_PERSISTENCE_ENABLED", "")
       |> String.trim()
       |> String.downcase() do
    "" -> config_env() == :prod and database_url != ""
    value when value in ["1", "true", "yes", "on"] -> true
    value when value in ["0", "false", "no", "off"] -> false
    value -> raise "invalid MANA_CHESS_PERSISTENCE_ENABLED value: #{inspect(value)}"
  end

if persistence_enabled and database_url == "" do
  raise "DATABASE_URL is required when Mana Chess persistence is enabled"
end

config :mana_chess_online, :persistence,
  enabled: persistence_enabled,
  store: ManaChessOnline.Persistence.EctoStore,
  writer: ManaChessOnline.Persistence.Writer

if persistence_enabled do
  pool_size =
    case Integer.parse(System.get_env("POOL_SIZE", "10")) do
      {value, ""} when value > 0 -> min(value, 50)
      _error -> 10
    end

  repo_config = [
    url: database_url,
    pool_size: pool_size,
    queue_target: 5_000,
    queue_interval: 1_000,
    timeout: 5_000
  ]

  repo_config =
    if System.get_env("ECTO_IPV6", "") in ["1", "true"],
      do: Keyword.put(repo_config, :socket_options, [:inet6]),
      else: repo_config

  repo_config =
    if System.get_env("MANA_CHESS_DATABASE_SSL", "") in ["1", "true"],
      do: Keyword.put(repo_config, :ssl, true),
      else: repo_config

  config :mana_chess_online, ManaChessOnline.Repo, repo_config
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :mana_chess_online, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :mana_chess_online, ManaChessOnlineWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "4000"))
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :mana_chess_online, ManaChessOnlineWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :mana_chess_online, ManaChessOnlineWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
