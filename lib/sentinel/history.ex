defmodule Sentinel.History do
  @moduledoc """
  24h rolling time-series for system metrics.

  Backed by a public ETS ordered_set keyed by unix-second timestamp.
  Rows older than 24h are evicted on each write. At the system
  collector's 10s tick rate this caps at ~8,640 rows; at 30s it would
  cap at ~2,880. The plan referenced 30s — actual collector cadence is
  10s, so we write at that rate and let the 24h window cap the rows.

  Row shape: `{ts, cpu_pct, mem_pct, swap_pct, load1}`.
  """

  use GenServer

  @table :sentinel_history
  @retention_seconds 24 * 60 * 60

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Writes a sample. Drops rows older than 24h.
  """
  def put(cpu_pct, mem_pct, swap_pct, load1, ts \\ System.system_time(:second)) do
    :ets.insert(@table, {ts, cpu_pct * 1.0, mem_pct * 1.0, swap_pct * 1.0, load1 * 1.0})
    evict(ts - @retention_seconds)
    :ok
  end

  @doc """
  Returns peaks (cpu, mem, swap, load1) and their timestamps for samples
  with `ts >= since_ts`. Returns `nil` if no samples in range.
  """
  def peak_since(since_ts) do
    rows =
      :ets.select(@table, [
        {{:"$1", :"$2", :"$3", :"$4", :"$5"}, [{:>=, :"$1", since_ts}],
         [{{:"$1", :"$2", :"$3", :"$4", :"$5"}}]}
      ])

    case rows do
      [] -> nil
      _ -> %{cpu: peak(rows, 1), mem: peak(rows, 2), swap: peak(rows, 3), load1: peak(rows, 4)}
    end
  end

  @doc """
  Returns peaks over the trailing `seconds` window.
  """
  def peak_over(seconds) when is_integer(seconds) and seconds > 0 do
    peak_since(System.system_time(:second) - seconds)
  end

  @doc """
  Returns the number of rows currently retained.
  """
  def size, do: :ets.info(@table, :size)

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:ordered_set, :public, :named_table, read_concurrency: true])
    {:ok, table}
  end

  # Private

  defp evict(cutoff_ts) do
    :ets.select_delete(@table, [{{:"$1", :_, :_, :_, :_}, [{:<, :"$1", cutoff_ts}], [true]}])
  end

  defp peak(rows, value_idx) do
    {ts, value} =
      Enum.reduce(rows, {nil, nil}, fn row, {best_ts, best_val} ->
        val = elem(row, value_idx)
        ts = elem(row, 0)
        if best_val == nil or val > best_val, do: {ts, val}, else: {best_ts, best_val}
      end)

    %{value: value, ts: ts}
  end
end
