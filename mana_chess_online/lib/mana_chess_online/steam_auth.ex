defmodule ManaChessOnline.SteamAuth do
  @moduledoc """
  Validates Steam tickets and owns the server-issued Steam session shape.

  Raw tickets and publisher keys are never returned or stored in the browser
  session. A successful session contains only verified identity, ownership,
  AppID, and verification time.
  """

  @session_key :steam_identity
  @min_ticket_characters 64
  @max_ticket_characters 8_192
  @max_clock_skew_seconds 60
  @max_app_id 4_294_967_295
  @protocol_version 1

  def session_key, do: @session_key

  def public_configuration do
    raw_config = Application.get_env(:mana_chess_online, :steam_auth, [])

    %{
      protocol_version: @protocol_version,
      configured: match?({:ok, _config}, configuration()),
      app_id: public_app_id(Keyword.get(raw_config, :app_id)),
      ticket_identity: public_ticket_identity(Keyword.get(raw_config, :ticket_identity))
    }
  end

  def authenticate(ticket) do
    with {:ok, config} <- configuration(),
         {:ok, normalized_ticket} <- normalize_ticket(ticket),
         {:ok, identity} <-
           config.client.authenticate_and_check(normalized_ticket, Map.drop(config, [:client])),
         {:ok, normalized_identity} <- normalize_identity(identity, config.app_id) do
      {:ok, normalized_identity}
    end
  end

  def session_payload(identity, verified_at \\ System.system_time(:second)) do
    %{
      "steam_id" => identity.steam_id,
      "owner_steam_id" => identity.owner_steam_id,
      "app_id" => Integer.to_string(identity.app_id),
      "verified_at" => verified_at,
      "ownership" => %{
        "permanent" => identity.permanent,
        "site_license" => identity.site_license,
        "time_expires" => identity.time_expires
      }
    }
  end

  def public_identity(identity) do
    %{
      steam_id: identity.steam_id,
      owner_steam_id: identity.owner_steam_id,
      app_id: identity.app_id,
      ownership: %{
        permanent: identity.permanent,
        site_license: identity.site_license,
        time_expires: identity.time_expires
      }
    }
  end

  def valid_session?(session, now \\ System.system_time(:second))

  def valid_session?(session, now) when is_map(session) and is_integer(now) do
    with {:ok, config} <- configuration(),
         {:ok, steam_id} <- normalize_steam_id(field(session, :steam_id)),
         {:ok, owner_steam_id} <- normalize_steam_id(field(session, :owner_steam_id)),
         {:ok, session_app_id} <- positive_integer(field(session, :app_id)),
         verified_at when is_integer(verified_at) <- field(session, :verified_at),
         true <- session_app_id == config.app_id,
         true <- verified_at <= now + @max_clock_skew_seconds,
         true <- now - verified_at <= config.session_ttl_seconds do
      steam_id != "" and owner_steam_id != ""
    else
      _error -> false
    end
  end

  def valid_session?(_session, _now), do: false

  def player_id(session, now \\ System.system_time(:second)) do
    if valid_session?(session, now) do
      {:ok, "steam_" <> field(session, :steam_id)}
    else
      :error
    end
  end

  def session_steam_id(session, now \\ System.system_time(:second)) do
    if valid_session?(session, now) do
      {:ok, field(session, :steam_id)}
    else
      :error
    end
  end

  defp configuration do
    config = Application.get_env(:mana_chess_online, :steam_auth, [])

    with {:ok, app_id} <- positive_integer(Keyword.get(config, :app_id)),
         true <- app_id <= @max_app_id,
         {:ok, publisher_key} <- required_string(Keyword.get(config, :publisher_key), 256),
         {:ok, ticket_identity} <-
           required_string(Keyword.get(config, :ticket_identity), 128),
         {:ok, session_ttl_seconds} <-
           positive_integer(Keyword.get(config, :session_ttl_seconds, 86_400)),
         true <- session_ttl_seconds <= 604_800,
         client when is_atom(client) <-
           Keyword.get(config, :client, ManaChessOnline.SteamWebApiClient),
         true <- Code.ensure_loaded?(client),
         true <- function_exported?(client, :authenticate_and_check, 2) do
      {:ok,
       %{
         app_id: app_id,
         publisher_key: publisher_key,
         ticket_identity: ticket_identity,
         session_ttl_seconds: session_ttl_seconds,
         client: client
       }}
    else
      _error -> {:error, :not_configured}
    end
  end

  defp normalize_ticket(ticket) when is_binary(ticket) do
    ticket = String.trim(ticket)
    ticket_size = byte_size(ticket)

    if ticket_size >= @min_ticket_characters and
         ticket_size <= @max_ticket_characters and
         rem(ticket_size, 2) == 0 and
         String.match?(ticket, ~r/\A[0-9A-Fa-f]+\z/) do
      {:ok, String.downcase(ticket)}
    else
      {:error, :malformed_ticket}
    end
  end

  defp normalize_ticket(_ticket), do: {:error, :malformed_ticket}

  defp normalize_identity(identity, expected_app_id) when is_map(identity) do
    with {:ok, steam_id} <- normalize_steam_id(field(identity, :steam_id)),
         {:ok, owner_steam_id} <- normalize_steam_id(field(identity, :owner_steam_id)),
         {:ok, app_id} <- positive_integer(field(identity, :app_id)) do
      owns_app = boolean(field(identity, :owns_app))
      publisher_banned = boolean(field(identity, :publisher_banned))
      user_canceled = boolean(field(identity, :user_canceled))

      cond do
        app_id != expected_app_id ->
          {:error, :invalid_ticket}

        publisher_banned ->
          {:error, :publisher_banned}

        not owns_app or user_canceled ->
          {:error, :ownership_required}

        true ->
          {:ok,
           %{
             steam_id: steam_id,
             owner_steam_id: owner_steam_id,
             app_id: app_id,
             owns_app: true,
             permanent: boolean(field(identity, :permanent)),
             site_license: boolean(field(identity, :site_license)),
             user_canceled: false,
             time_expires: normalized_expiry(field(identity, :time_expires)),
             vac_banned: boolean(field(identity, :vac_banned)),
             publisher_banned: false
           }}
      end
    end
  end

  defp normalize_identity(_identity, _expected_app_id), do: {:error, :invalid_ticket}

  defp public_app_id(value) do
    case positive_integer(value) do
      {:ok, app_id} when app_id <= @max_app_id -> app_id
      _error -> nil
    end
  end

  defp public_ticket_identity(value) do
    case required_string(value, 128) do
      {:ok, ticket_identity} -> ticket_identity
      _error -> nil
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) do
    case Integer.parse(String.trim(to_string(value || ""))) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _error -> {:error, :invalid_integer}
    end
  end

  defp required_string(value, max_bytes) do
    value = String.trim(to_string(value || ""))

    if value != "" and byte_size(value) <= max_bytes and
         not String.match?(value, ~r/[\x00-\x1f\x7f]/) do
      {:ok, value}
    else
      {:error, :invalid_string}
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

  defp normalized_expiry(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.slice(0, 80)
  end

  defp boolean(value), do: value in [true, 1, "1", "true", "TRUE"]

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
