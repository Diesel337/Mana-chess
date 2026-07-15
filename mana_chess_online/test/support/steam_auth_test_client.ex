defmodule ManaChessOnline.SteamAuthTestClient do
  @moduledoc false

  @behaviour ManaChessOnline.SteamAuthClient

  @response_key {__MODULE__, :response}

  def put_response(response), do: Process.put(@response_key, response)
  def clear_response, do: Process.delete(@response_key)

  @impl true
  def authenticate_and_check(ticket, config) do
    send(self(), {__MODULE__, :called, ticket, config})
    Process.get(@response_key, {:error, :upstream_unavailable})
  end
end
