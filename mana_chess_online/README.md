# ManaChessOnline

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Lobby stress smoke

Run a local logical-client stress pass against the in-app lobby process:

```bash
mix run scripts/lobby_stress.exs -- --players 100
```

Useful options:

```bash
mix run scripts/lobby_stress.exs -- --players 100 --practice 20 --private-pairs 40 --concurrency 32 --settle-ms 500
mix run scripts/lobby_stress.exs -- --players 100 --json
```

This is an internal OTP/lobby smoke, not a replacement for real WebSocket or Steam-client load tests.
