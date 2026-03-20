defmodule Sentinel.MetricStore do
  @moduledoc """
  ETS-backed in-memory store for the latest metric snapshots.

  Collectors write metrics here; the Evaluator and Telegram bot read from it.
  The ETS table is `:public` so collectors can write directly without
  going through the GenServer process.
  """

  use GenServer

  @table :sentinel_metrics

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def put(collector, metric, value) do
    :ets.insert(@table, {{collector, metric}, value, System.system_time(:second)})
    :ok
  end

  def get(collector, metric) do
    case :ets.lookup(@table, {collector, metric}) do
      [{_key, value, timestamp}] -> {value, timestamp}
      [] -> nil
    end
  end

  def snapshot do
    @table
    |> :ets.tab2list()
    |> Enum.reduce(%{}, fn {{collector, metric}, value, timestamp}, acc ->
      acc
      |> Map.put_new(collector, %{})
      |> put_in([collector, metric], {value, timestamp})
    end)
  end

  def snapshot(collector) do
    @table
    |> :ets.match_object({{collector, :_}, :_, :_})
    |> Enum.reduce(%{}, fn {{_collector, metric}, value, timestamp}, acc ->
      Map.put(acc, metric, {value, timestamp})
    end)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, table}
  end
end
