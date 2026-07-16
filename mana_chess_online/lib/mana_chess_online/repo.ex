defmodule ManaChessOnline.Repo do
  use Ecto.Repo,
    otp_app: :mana_chess_online,
    adapter: Ecto.Adapters.Postgres
end
