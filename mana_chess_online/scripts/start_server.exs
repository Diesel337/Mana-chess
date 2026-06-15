root = Path.expand("..", __DIR__)

root
|> Path.join("_build/dev/lib/*/ebin")
|> Path.wildcard()
|> Enum.each(fn path -> Code.append_path(String.to_charlist(path)) end)

Application.put_env(:phoenix, :json_library, Jason)
Application.put_env(:phoenix, :serve_endpoints, true)

Application.put_env(:phoenix_live_view, :colocated_js,
  disable_symlink_warning: true
)

Application.put_env(:mana_chess_online, :dns_cluster_query, :ignore)

Application.put_env(:mana_chess_online, ManaChessOnlineWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  server: true,
  secret_key_base: "6krfz0eK+o0Mzm/kswtjIj2czjW35QtJcpY+DTRsioJtaxLcKh6YIxtkONyC5CHs",
  pubsub_server: ManaChessOnline.PubSub,
  live_view: [signing_salt: "+U0Hw9HM"],
  render_errors: [
    formats: [html: ManaChessOnlineWeb.ErrorHTML, json: ManaChessOnlineWeb.ErrorJSON],
    layout: false
  ]
)

{:ok, _apps} = Application.ensure_all_started(:mana_chess_online)

IO.puts("Mana Chess Online listo en http://localhost:4000")
Process.sleep(:infinity)
