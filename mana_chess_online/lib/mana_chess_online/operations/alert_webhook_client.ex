defmodule ManaChessOnline.Operations.AlertWebhookClient do
  @moduledoc """
  Delivers sanitized operational alerts to a configured HTTPS webhook.

  Response bodies and transport exceptions are deliberately collapsed into
  stable error codes so provider details cannot leak into application logs.
  """

  @request_options [
    retry: false,
    redirect: false,
    receive_timeout: 5_000,
    connect_options: [timeout: 3_000]
  ]

  def deliver(url, token, payload, request_options \\ [])
      when is_binary(url) and is_binary(token) and is_map(payload) and
             is_list(request_options) do
    options =
      @request_options
      |> Keyword.merge(request_options)
      |> Keyword.put(:json, payload)
      |> maybe_put_authorization(token)

    case Req.post(url, options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} when status in [408, 429] ->
        {:error, "http_retryable"}

      {:ok, %Req.Response{status: status}} when status in 400..499 ->
        {:error, "http_4xx"}

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        {:error, "http_5xx"}

      {:ok, %Req.Response{}} ->
        {:error, "unexpected_status"}

      {:error, _exception} ->
        {:error, "network_error"}
    end
  rescue
    _exception -> {:error, "request_exception"}
  catch
    _kind, _reason -> {:error, "request_exit"}
  end

  defp maybe_put_authorization(options, ""), do: options

  defp maybe_put_authorization(options, token) do
    Keyword.update(options, :headers, [{"authorization", "Bearer " <> token}], fn headers ->
      [{"authorization", "Bearer " <> token} | headers]
    end)
  end
end
