defmodule ManaChessOnline.Persistence.WriterTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Persistence.Writer

  defmodule Store do
    def persist({:test, %{reply_to: pid, result: result}} = event) do
      send(pid, {:stored, event})
      result
    end
  end

  test "persists outside the caller and tracks successful writes" do
    {:ok, writer} =
      start_supervised({Writer, name: nil, enabled: true, store: Store})

    event = {:test, %{reply_to: self(), result: :ok}}
    assert :ok = Writer.record(writer, event)
    assert_receive {:stored, ^event}

    status = Writer.status(writer)
    assert status.persisted_count == 1
    assert status.failed_count == 0
    assert status.last_event == "test"
    assert status.running
  end

  test "contains store failures without crashing" do
    {:ok, writer} =
      start_supervised({Writer, name: nil, enabled: true, store: Store})

    event = {:test, %{reply_to: self(), result: {:error, :database_down}}}
    Writer.record(writer, event)
    assert_receive {:stored, ^event}

    status = Writer.status(writer)
    assert Process.alive?(writer)
    assert status.failed_count == 1
    assert status.last_error == "write_failed"
  end

  test "skips writes cleanly when persistence is disabled" do
    {:ok, writer} =
      start_supervised({Writer, name: nil, enabled: false, store: Store})

    Writer.record(writer, {:test, %{reply_to: self(), result: :ok}})
    refute_receive {:stored, _event}, 50
    assert Writer.status(writer).skipped_count == 1
  end
end
