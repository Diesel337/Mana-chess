defmodule ManaChessOnline.Persistence.Writer do
  @moduledoc false

  use GenServer

  require Logger

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def record(event), do: record(__MODULE__, event)
  def record(server, event), do: GenServer.cast(server, {:record, event})

  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @impl true
  def init(opts) do
    {:ok,
     %{
       enabled: Keyword.get(opts, :enabled, false),
       store: Keyword.fetch!(opts, :store),
       persisted_count: 0,
       failed_count: 0,
       skipped_count: 0,
       last_event: nil,
       last_error: nil,
       last_error_at: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    mailbox = Process.info(self(), :message_queue_len) |> elem(1)

    {:reply,
     state
     |> Map.drop([:store])
     |> Map.put(:running, true)
     |> Map.put(:mailbox, mailbox), state}
  end

  @impl true
  def handle_cast({:record, _event}, %{enabled: false} = state) do
    {:noreply, %{state | skipped_count: state.skipped_count + 1}}
  end

  def handle_cast({:record, event}, state) do
    event_type = event_type(event)

    case persist(state.store, event) do
      :ok ->
        {:noreply,
         %{
           state
           | persisted_count: state.persisted_count + 1,
             last_event: event_type,
             last_error: nil,
             last_error_at: nil
         }}

      {:error, code} ->
        Logger.warning("Mana Chess persistence write failed type=#{event_type} code=#{code}")

        {:noreply,
         %{
           state
           | failed_count: state.failed_count + 1,
             last_event: event_type,
             last_error: code,
             last_error_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }}
    end
  end

  defp persist(store, event) do
    try do
      case store.persist(event) do
        :ok -> :ok
        {:ok, _value} -> :ok
        {:error, %Ecto.Changeset{}} -> {:error, "validation_error"}
        {:error, _reason} -> {:error, "write_failed"}
        _result -> {:error, "invalid_store_result"}
      end
    rescue
      _error -> {:error, "write_exception"}
    catch
      _kind, _reason -> {:error, "write_exit"}
    end
  end

  defp event_type({type, _attrs}) when is_atom(type), do: Atom.to_string(type)
  defp event_type(_event), do: "unknown"
end
