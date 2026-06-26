defmodule ManaChessOnlineWeb.AdminLive do
  use ManaChessOnlineWeb, :live_view

  alias ManaChessOnline.GameLobby

  import ManaChessOnlineWeb.GameBrandComponents

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin | Mana Chess")
     |> assign(:player_id, Map.get(session, "player_id"))
     |> assign(:authenticated?, false)
     |> assign(:settings, GameLobby.global_settings())
     |> assign(:metrics, GameLobby.metrics())}
  end

  @impl true
  def handle_event("login", %{"password" => password}, socket) do
    if password == admin_password() do
      {:noreply, assign(socket, authenticated?: true, metrics: GameLobby.metrics())}
    else
      {:noreply, put_flash(socket, :error, "Clave incorrecta.")}
    end
  end

  def handle_event("save_settings", params, socket) do
    if socket.assigns.authenticated? do
      settings = GameLobby.update_global_settings(params)
      socket = assign(socket, settings: settings, metrics: GameLobby.metrics())

      if Map.get(params, "apply_practice") == "true" do
        apply_settings_to_practice(socket)
      else
        {:noreply, put_flash(socket, :info, "Configuracion global guardada.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Inicia sesion para guardar.")}
    end
  end

  def handle_event("refresh_metrics", _params, socket) do
    if socket.assigns.authenticated? do
      {:noreply, assign(socket, :metrics, GameLobby.metrics())}
    else
      {:noreply, put_flash(socket, :error, "Inicia sesion para ver metricas.")}
    end
  end

  defp apply_settings_to_practice(socket) do
    socket = assign(socket, :metrics, GameLobby.metrics())

    case GameLobby.apply_global_settings_to_practice(socket.assigns.player_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Configuracion guardada y aplicada a tu practica.")}

      {:error, :no_practice} ->
        {:noreply, put_flash(socket, :error, "Abre Modo practica en este navegador para aplicar ahi.")}
    end
  end

  defp admin_password do
    System.get_env("ADMIN_PASSWORD") || "mana"
  end

  defp setting_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp setting_value(value), do: value

  defp metric_value(value) when is_integer(value), do: Integer.to_string(value)
  defp metric_value(value), do: to_string(value)

  defp metric_kb(value), do: metric_value(value) <> " KB"

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mc-shell">
      <section class="mc-game mc-admin">
        <div class="mc-header">
          <.brand_lockup title="Admin" detail="Balance y configuracion" />
          <a class="mc-admin-link" href={~p"/"}>Volver al juego</a>
        </div>

        <form :if={!@authenticated?} class="mc-settings mc-admin-login" phx-submit="login">
          <div class="mc-settings-head">
            <h2>Acceso</h2>
            <button type="submit">Entrar</button>
          </div>
          <label>
            <span>Clave admin</span>
            <input name="password" type="password" autocomplete="current-password" autofocus />
          </label>
        </form>

        <form :if={@authenticated?} class="mc-settings" phx-submit="save_settings">
          <div class="mc-settings-head">
            <h2>Configuracion global</h2>
            <div class="mc-settings-actions">
              <button type="submit">Guardar</button>
              <button type="submit" name="apply_practice" value="true">Guardar y aplicar a practica</button>
            </div>
          </div>
          <p>Estos valores se aplican a partidas nuevas y salas vacias. Se guardan en el servidor.</p>

          <div class="mc-settings-grid">
            <label>
              <span>Peon</span>
              <input name="pawn" type="number" min="0" max="99" step="0.25" value={setting_value(@settings.costs.pawn)} />
            </label>
            <label>
              <span>Caballo</span>
              <input name="knight" type="number" min="0" max="99" step="0.25" value={setting_value(@settings.costs.knight)} />
            </label>
            <label>
              <span>Alfil</span>
              <input name="bishop" type="number" min="0" max="99" step="0.25" value={setting_value(@settings.costs.bishop)} />
            </label>
            <label>
              <span>Torre</span>
              <input name="rook" type="number" min="0" max="99" step="0.25" value={setting_value(@settings.costs.rook)} />
            </label>
            <label>
              <span>Reina</span>
              <input name="queen" type="number" min="0" max="99" step="0.25" value={setting_value(@settings.costs.queen)} />
            </label>
            <label>
              <span>Rey</span>
              <input name="king" type="number" min="0" max="99" step="0.25" value={setting_value(@settings.costs.king)} />
            </label>
            <label>
              <span>Cooldown global</span>
              <input name="cooldown_seconds" type="number" min="0" max="60" step="0.25" value={setting_value(@settings.cooldown_seconds)} disabled={!@settings.cooldown_enabled} />
            </label>
            <label>
              <span>Tiempo movida bot</span>
              <input name="bot_move_seconds" type="number" min="0.25" max="30" step="0.25" value={setting_value(@settings.bot_move_seconds)} />
            </label>
            <label class="mc-toggle">
              <span>Sin cooldown</span>
              <input type="hidden" name="cooldown_enabled" value="true" />
              <input name="cooldown_enabled" type="checkbox" value="false" checked={!@settings.cooldown_enabled} />
            </label>
            <label>
              <span>Elixir maximo</span>
              <input name="max_elixir" type="number" min="1" max="99" step="0.5" value={setting_value(@settings.max_elixir)} />
            </label>
            <label>
              <span>Elixir inicial</span>
              <input name="initial_elixir" type="number" min="0" max={setting_value(@settings.max_elixir)} step="0.5" value={setting_value(@settings.initial_elixir)} />
            </label>
            <label>
              <span>Regeneracion / seg</span>
              <input name="regen_per_second" type="number" min="0" max="20" step="0.25" value={setting_value(@settings.regen_per_second)} />
            </label>
            <label>
              <span>Recuperacion captura %</span>
              <input name="capture_refund_percent" type="number" min="0" max="100" step="5" value={setting_value(@settings.capture_refund_percent)} />
            </label>
          </div>
        </form>

        <section :if={@authenticated?} class="mc-settings mc-admin-metrics">
          <div class="mc-settings-head">
            <h2>Salud del servidor</h2>
            <div class="mc-settings-actions">
              <button type="button" phx-click="refresh_metrics">Actualizar</button>
            </div>
          </div>
          <p>Snapshot local para preparar carga Steam: partidas, procesos, memoria y colas.</p>

          <div class="mc-metrics-grid">
            <div class="mc-metric"><span>Partidas</span><strong>{metric_value(@metrics.game_count)}</strong></div>
            <div class="mc-metric"><span>Publicas</span><strong>{metric_value(@metrics.public_game_count)}</strong></div>
            <div class="mc-metric"><span>Privadas</span><strong>{metric_value(@metrics.private_game_count)}</strong></div>
            <div class="mc-metric"><span>Practica</span><strong>{metric_value(@metrics.practice_game_count)}</strong></div>
            <div class="mc-metric"><span>Jugando</span><strong>{metric_value(@metrics.playing_game_count)}</strong></div>
            <div class="mc-metric"><span>Esperando</span><strong>{metric_value(@metrics.waiting_game_count)}</strong></div>
            <div class="mc-metric"><span>Bots activos</span><strong>{metric_value(@metrics.bot_game_count)}</strong></div>
            <div class="mc-metric"><span>Movs en cola</span><strong>{metric_value(@metrics.queued_move_count)}</strong></div>
            <div class="mc-metric"><span>GameServers</span><strong>{metric_value(@metrics.game_server_count)}</strong></div>
            <div class="mc-metric"><span>Mailbox total</span><strong>{metric_value(@metrics.game_server_mailbox_total)}</strong></div>
            <div class="mc-metric"><span>Mailbox max</span><strong>{metric_value(@metrics.game_server_mailbox_max)}</strong></div>
            <div class="mc-metric"><span>Rate buckets</span><strong>{metric_value(@metrics.rate_limit_bucket_count)}</strong></div>
            <div class="mc-metric"><span>Mem VM</span><strong>{metric_kb(@metrics.memory_total_kb)}</strong></div>
            <div class="mc-metric"><span>Mem juegos</span><strong>{metric_kb(@metrics.game_server_memory_kb)}</strong></div>
            <div class="mc-metric"><span>Procesos VM</span><strong>{metric_value(@metrics.process_count)}</strong></div>
            <div class="mc-metric"><span>Run queue</span><strong>{metric_value(@metrics.run_queue)}</strong></div>
          </div>
        </section>
      </section>
    </main>
    """
  end
end
