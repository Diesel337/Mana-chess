defmodule ManaChessOnline.Operations.LogFormatter do
  @moduledoc false

  @metadata_fields [
    :code,
    :component,
    :count,
    :duration_ms,
    :event,
    :event_at,
    :event_type,
    :method,
    :reason_class,
    :request_id,
    :route,
    :source,
    :status,
    :suppressed_since_last
  ]
  @credential_url ~r/\b(?:postgres(?:ql)?|https?):\/\/[^\s"']+/iu
  @long_hex ~r/\b[0-9a-f]{64,}\b/iu
  @sensitive_assignment ~r/\b(password|secret|token|ticket|cookie|authorization|database_url|publisher_key|qa_key)\b\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,}\]]+)/iu

  def format(level, message, timestamp, metadata) do
    runtime = Application.get_env(:mana_chess_online, :runtime_metadata, [])

    payload =
      metadata
      |> Map.new()
      |> Map.take(@metadata_fields)
      |> sanitize_metadata()
      |> Map.merge(%{
        environment: sanitize_value(Keyword.get(runtime, :environment, "unknown")),
        level: Atom.to_string(level),
        message: safe_message(message),
        release: sanitize_value(Keyword.get(runtime, :release, "local")),
        service: "mana_chess_online",
        timestamp: iso8601(timestamp)
      })

    [Jason.encode_to_iodata!(payload), ?\n]
  rescue
    _error ->
      [
        "{\"level\":\"error\",\"message\":\"log_format_failed\",\"service\":\"mana_chess_online\"}\n"
      ]
  end

  defp sanitize_metadata(metadata) do
    Enum.reduce(metadata, %{}, fn {key, value}, sanitized ->
      case sanitize_value(value) do
        nil -> sanitized
        value -> Map.put(sanitized, key, value)
      end
    end)
  end

  defp sanitize_value(nil), do: nil
  defp sanitize_value(value) when is_binary(value), do: String.slice(value, 0, 160)
  defp sanitize_value(value) when is_atom(value), do: Atom.to_string(value)

  defp sanitize_value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: value

  defp sanitize_value(_value), do: nil

  defp safe_message(message) do
    message
    |> IO.chardata_to_string()
    |> redact_message()
    |> String.slice(0, 8_000)
  rescue
    _error -> "unformattable_log_message"
  end

  defp redact_message(message) do
    message = Regex.replace(@credential_url, message, "[REDACTED_URL]")

    message =
      Regex.replace(@sensitive_assignment, message, fn _match, key, _value ->
        key <> "=[REDACTED]"
      end)

    Regex.replace(@long_hex, message, "[REDACTED_HEX]")
  end

  defp iso8601({{year, month, day}, {hour, minute, second, millisecond}}) do
    :io_lib.format(
      "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
      [year, month, day, hour, minute, second, millisecond]
    )
    |> IO.iodata_to_binary()
  end

  defp iso8601(_timestamp), do: "unknown"
end
