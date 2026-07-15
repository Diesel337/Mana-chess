defmodule ManaChessOnline.SteamWebApiClient do
  @moduledoc """
  Secure-server client for Steam ticket authentication and app ownership.
  """

  @behaviour ManaChessOnline.SteamAuthClient

  @api_origin "https://partner.steam-api.com"
  @request_options [
    retry: false,
    redirect: false,
    receive_timeout: 5_000,
    connect_options: [timeout: 3_000]
  ]

  @impl true
  def authenticate_and_check(ticket, config) do
    with {:ok, ticket_identity} <- authenticate_ticket(ticket, config),
         :ok <- reject_publisher_ban(ticket_identity),
         {:ok, ownership} <- check_ownership(ticket_identity.steam_id, config),
         :ok <- require_ownership(ownership) do
      {:ok,
       Map.merge(ticket_identity, ownership)
       |> Map.put(:app_id, config.app_id)}
    end
  end

  defp authenticate_ticket(ticket, config) do
    params = [
      key: config.publisher_key,
      appid: config.app_id,
      ticket: ticket,
      identity: config.ticket_identity
    ]

    with {:ok, body} <- request("/ISteamUserAuth/AuthenticateUserTicket/v1/", params, config),
         %{} = auth <- get_in(body, ["response", "params"]),
         "OK" <- Map.get(auth, "result"),
         {:ok, steam_id} <- normalize_steam_id(Map.get(auth, "steamid")) do
      {:ok,
       %{
         steam_id: steam_id,
         owner_steam_id: normalized_owner_id(Map.get(auth, "ownersteamid"), steam_id),
         vac_banned: truthy?(Map.get(auth, "vacbanned")),
         publisher_banned: truthy?(Map.get(auth, "publisherbanned"))
       }}
    else
      {:error, :upstream_unavailable} = error -> error
      _error -> {:error, :invalid_ticket}
    end
  end

  defp check_ownership(steam_id, config) do
    params = [key: config.publisher_key, steamid: steam_id, appid: config.app_id]

    with {:ok, body} <- request("/ISteamUser/CheckAppOwnership/v4/", params, config),
         %{} = ownership <- ownership_body(body) do
      {:ok,
       %{
         owner_steam_id: normalized_owner_id(Map.get(ownership, "ownersteamid"), steam_id),
         owns_app: truthy?(Map.get(ownership, "ownsapp")),
         permanent: truthy?(Map.get(ownership, "permanent")),
         site_license: truthy?(Map.get(ownership, "sitelicense")),
         user_canceled: truthy?(Map.get(ownership, "usercanceled")),
         time_expires: Map.get(ownership, "timeexpires", "")
       }}
    else
      {:error, :upstream_unavailable} = error -> error
      _error -> {:error, :upstream_unavailable}
    end
  end

  defp request(path, params, config) do
    options =
      @request_options
      |> Keyword.merge(Map.get(config, :request_options, []))
      |> Keyword.put(:params, params)

    case Req.get(@api_origin <> path, options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{}} ->
        {:error, :upstream_unavailable}

      {:error, _exception} ->
        {:error, :upstream_unavailable}
    end
  rescue
    _exception -> {:error, :upstream_unavailable}
  end

  defp ownership_body(body) do
    Map.get(body, "appownership") ||
      get_in(body, ["response", "appownership"]) ||
      if(Map.has_key?(body, "ownsapp"), do: body)
  end

  defp reject_publisher_ban(%{publisher_banned: true}), do: {:error, :publisher_banned}
  defp reject_publisher_ban(_identity), do: :ok

  defp require_ownership(%{owns_app: true, user_canceled: false}), do: :ok
  defp require_ownership(_ownership), do: {:error, :ownership_required}

  defp normalized_owner_id(owner_steam_id, fallback) do
    case normalize_steam_id(owner_steam_id) do
      {:ok, steam_id} -> steam_id
      _error -> fallback
    end
  end

  defp normalize_steam_id(value) do
    value = String.trim(to_string(value || ""))

    if String.match?(value, ~r/\A[0-9]{16,20}\z/) do
      {:ok, value}
    else
      {:error, :invalid_steam_id}
    end
  end

  defp truthy?(value), do: value in [true, 1, "1", "true", "TRUE"]
end
