# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mana_chess_online,
  ecto_repos: [ManaChessOnline.Repo],
  generators: [timestamp_type: :utc_datetime_usec],
  persistence: [
    enabled: false,
    store: ManaChessOnline.Persistence.EctoStore,
    writer: ManaChessOnline.Persistence.Writer
  ]

config :mana_chess_online, ManaChessOnline.Repo,
  migration_primary_key: [name: :id, type: :bigserial],
  migration_foreign_key: [type: :bigint]

# Configure the endpoint
config :mana_chess_online, ManaChessOnlineWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ManaChessOnlineWeb.ErrorHTML, json: ManaChessOnlineWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ManaChessOnline.PubSub,
  live_view: [signing_salt: "+U0Hw9HM"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix_live_view, :colocated_js, disable_symlink_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
