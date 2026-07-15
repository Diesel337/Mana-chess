defmodule ManaChessOnline.SteamAuthClient do
  @moduledoc """
  Contract for verifying a Steam Web API ticket and the associated app license.
  """

  @type config :: %{
          app_id: pos_integer(),
          publisher_key: String.t(),
          ticket_identity: String.t()
        }

  @type identity :: %{
          required(:steam_id) => String.t(),
          required(:owner_steam_id) => String.t(),
          required(:app_id) => pos_integer(),
          required(:owns_app) => boolean(),
          optional(:permanent) => boolean(),
          optional(:site_license) => boolean(),
          optional(:user_canceled) => boolean(),
          optional(:time_expires) => String.t(),
          optional(:vac_banned) => boolean(),
          optional(:publisher_banned) => boolean()
        }

  @callback authenticate_and_check(String.t(), config()) ::
              {:ok, identity()}
              | {:error,
                 :invalid_ticket
                 | :ownership_required
                 | :publisher_banned
                 | :upstream_unavailable}
end
