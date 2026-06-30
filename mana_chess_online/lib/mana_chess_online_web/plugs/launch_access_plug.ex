defmodule ManaChessOnlineWeb.LaunchAccessPlug do
  @moduledoc """
  Runtime launch gate for the Steam-first release path.

  The default mode is open so today's Railway deployment remains a QA/backend
  surface. Setting `MANA_CHESS_LAUNCH_ACCESS=steam_required` blocks public game
  routes unless a future Steam-verified session exists or an explicit QA bypass
  key is provided.
  """

  import Plug.Conn

  @behaviour Plug

  @session_qa_key :launch_access
  @session_steam_key :steam_verified

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    cond do
      admin_path?(conn) ->
        conn

      not steam_required?() ->
        conn

      steam_session?(conn) ->
        conn

      true ->
        case qa_bypass(conn) do
          {:ok, conn} -> conn
          :error -> reject(conn)
        end
    end
  end

  defp admin_path?(%Plug.Conn{path_info: ["admin" | _rest]}), do: true
  defp admin_path?(_conn), do: false

  defp steam_required? do
    mode =
      launch_access_config()
      |> Keyword.get(:mode, "open")
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    mode in ["steam_required", "steam"]
  end

  defp steam_session?(conn) do
    get_session(conn, @session_steam_key) in [true, "true", "1", "steam"]
  end

  defp qa_bypass(conn) do
    cond do
      get_session(conn, @session_qa_key) == "qa" ->
        {:ok, conn}

      qa_key() == "" ->
        :error

      secure_match?(qa_token(conn), qa_key()) ->
        {:ok, put_session(conn, @session_qa_key, "qa")}

      true ->
        :error
    end
  end

  defp qa_token(conn) do
    conn = fetch_query_params(conn)

    conn
    |> get_req_header("x-mana-chess-qa-key")
    |> List.first()
    |> case do
      nil -> Map.get(conn.query_params, "qa_key", "")
      token -> token
    end
    |> to_string()
    |> String.trim()
  end

  defp qa_key do
    launch_access_config()
    |> Keyword.get(:qa_bypass_key, "")
    |> to_string()
    |> String.trim()
  end

  defp launch_access_config do
    Application.get_env(:mana_chess_online, :launch_access, [])
  end

  defp secure_match?("", _expected), do: false
  defp secure_match?(_token, ""), do: false

  defp secure_match?(token, expected) when byte_size(token) == byte_size(expected) do
    Plug.Crypto.secure_compare(token, expected)
  end

  defp secure_match?(_token, _expected), do: false

  defp reject(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(403, blocked_html())
    |> halt()
  end

  defp blocked_html do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Mana Chess</title>
        <style>
          :root {
            color-scheme: dark;
            --bg: #111713;
            --text: #f7f2e8;
            --muted: #b7c3b3;
            --gold: #e6bd68;
          }

          * {
            box-sizing: border-box;
          }

          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: clamp(20px, 6vw, 56px);
            background: var(--bg);
            color: var(--text);
            font-family: Arial, Helvetica, sans-serif;
          }

          main {
            width: min(680px, 100%);
            display: grid;
            gap: 12px;
          }

          .eyebrow {
            margin: 0;
            color: var(--gold);
            font-size: 12px;
            font-weight: 900;
            text-transform: uppercase;
          }

          h1 {
            margin: 0;
            color: var(--gold);
            font-size: clamp(32px, 9vw, 56px);
            line-height: 1.05;
          }

          p {
            max-width: 60ch;
            margin: 0;
            color: var(--muted);
            font-size: clamp(15px, 4vw, 18px);
            line-height: 1.45;
            overflow-wrap: anywhere;
          }
        </style>
      </head>
      <body>
        <main>
          <p class="eyebrow">Steam access required</p>
          <h1>Mana Chess</h1>
          <p>This launch build requires Steam access. QA access must use an explicit protected bypass.</p>
        </main>
      </body>
    </html>
    """
  end
end
