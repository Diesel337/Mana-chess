defmodule ManaChessOnline.GameMetrics do
  @moduledoc false

  def snapshot(
        games,
        game_server_pids,
        child_count,
        rate_limits,
        measured_at_ms \\ System.system_time(:millisecond),
        capacity \\ %{}
      ) do
    game_values = Map.values(games)
    process_stats = process_stats(game_server_pids)

    %{
      measured_at_ms: measured_at_ms,
      game_count: map_size(games),
      public_game_count: count_games(game_values, &public_game?/1),
      private_game_count: count_games(game_values, &Map.get(&1, :private?, false)),
      practice_game_count: count_games(game_values, &Map.get(&1, :practice?, false)),
      waiting_game_count: count_status(game_values, :waiting),
      ready_game_count: count_status(game_values, :ready),
      starting_game_count: Enum.count(game_values, &starting?/1),
      playing_game_count: count_status(game_values, :playing),
      bot_game_count: count_games(game_values, &Map.get(&1, :bot_enabled?, false)),
      queued_move_count:
        Enum.reduce(game_values, 0, fn game, total ->
          total + length(Map.get(game, :queue, []))
        end),
      rate_limit_bucket_count: map_size(rate_limits),
      game_server_count: child_count_value(child_count, :active),
      game_server_mailbox_total: process_stats.mailbox_total,
      game_server_mailbox_max: process_stats.mailbox_max,
      game_server_memory_kb: div(process_stats.memory_bytes, 1024),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      memory_total_kb: memory_kb(:total),
      memory_processes_kb: memory_kb(:processes),
      memory_binary_kb: memory_kb(:binary),
      run_queue: :erlang.statistics(:run_queue),
      dynamic_game_count: Map.get(capacity, :dynamic_game_count, 0),
      max_dynamic_games: Map.get(capacity, :max_dynamic_games, 0),
      dynamic_capacity_available: Map.get(capacity, :dynamic_capacity_available, 0),
      capacity_rejected_count: Map.get(capacity, :capacity_rejected_count, 0),
      cleaned_dynamic_game_count: Map.get(capacity, :cleaned_dynamic_game_count, 0)
    }
  end

  defp process_stats(pids) do
    pids
    |> Enum.uniq()
    |> Enum.reduce(%{mailbox_total: 0, mailbox_max: 0, memory_bytes: 0}, fn pid, acc ->
      case process_info(pid) do
        nil ->
          acc

        %{mailbox: mailbox, memory: memory} ->
          %{
            mailbox_total: acc.mailbox_total + mailbox,
            mailbox_max: max(acc.mailbox_max, mailbox),
            memory_bytes: acc.memory_bytes + memory
          }
      end
    end)
  end

  defp process_info(pid) when is_pid(pid) do
    case Process.info(pid, [:message_queue_len, :memory]) do
      nil ->
        nil

      info ->
        %{
          mailbox: Keyword.get(info, :message_queue_len, 0),
          memory: Keyword.get(info, :memory, 0)
        }
    end
  end

  defp process_info(_pid), do: nil

  defp public_game?(game) do
    !Map.get(game, :private?, false) && !Map.get(game, :practice?, false)
  end

  defp count_games(games, predicate), do: Enum.count(games, predicate)

  defp count_status(games, status), do: Enum.count(games, &(Map.get(&1, :status) == status))

  defp starting?(%{status: {:starting, _starts_at}}), do: true
  defp starting?(_game), do: false

  defp child_count_value(child_count, key) when is_map(child_count),
    do: Map.get(child_count, key, 0)

  defp child_count_value(_child_count, _key), do: 0

  defp memory_kb(type), do: div(:erlang.memory(type), 1024)
end
