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
mix run scripts/lobby_stress.exs -- --profile 100
mix run scripts/lobby_stress.exs -- --profile 500
```

Useful options:

```bash
mix run scripts/lobby_stress.exs -- --players 100 --practice 20 --private-pairs 40 --concurrency 32 --settle-ms 500
mix run scripts/lobby_stress.exs -- --profile 500 --max-total-ms 90000 --max-mailbox 10 --max-run-queue 20
mix run scripts/lobby_stress.exs -- --profile 100 --operation-timeout-ms 30000 --json
```

Profiles are local logical-client runs. Profile `500` uses 100 practice players, 150 private matches, and 100 watchers. This is an internal OTP/lobby smoke, not a replacement for real WebSocket or Steam-client load tests.
