defmodule ManaChessOnline.GameRegistry do
  @moduledoc false

  @name __MODULE__

  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @name)

  def via(game_id) when is_binary(game_id), do: {:via, Registry, {@name, game_id}}

  def lookup(game_id) when is_binary(game_id) do
    case Registry.lookup(@name, game_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  def whereis(game_id) when is_binary(game_id) do
    case lookup(game_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def registered?(game_id) when is_binary(game_id), do: match?({:ok, _pid}, lookup(game_id))
end
