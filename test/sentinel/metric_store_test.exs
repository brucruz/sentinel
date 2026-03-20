defmodule Sentinel.MetricStoreTest do
  use ExUnit.Case, async: false

  setup do
    store = start_supervised!(Sentinel.MetricStore)
    %{store: store}
  end

  test "put and get a metric" do
    :ok = Sentinel.MetricStore.put(:system, :cpu_percent, 42.5)
    {value, timestamp} = Sentinel.MetricStore.get(:system, :cpu_percent)

    assert value == 42.5
    assert is_integer(timestamp)
  end

  test "get returns nil for missing key" do
    assert Sentinel.MetricStore.get(:system, :nonexistent) == nil
  end

  test "put overwrites previous value" do
    :ok = Sentinel.MetricStore.put(:system, :cpu_percent, 10.0)
    :ok = Sentinel.MetricStore.put(:system, :cpu_percent, 90.0)

    {value, _ts} = Sentinel.MetricStore.get(:system, :cpu_percent)
    assert value == 90.0
  end

  test "snapshot returns all entries grouped by collector" do
    :ok = Sentinel.MetricStore.put(:system, :cpu_percent, 42.5)
    :ok = Sentinel.MetricStore.put(:system, :memory, %{percent: 50.0})
    :ok = Sentinel.MetricStore.put(:disk, "/", %{percent: 38})

    snapshot = Sentinel.MetricStore.snapshot()

    assert map_size(snapshot) == 2
    assert %{cpu_percent: {42.5, _}, memory: {%{percent: 50.0}, _}} = snapshot.system
    assert %{"/" => {%{percent: 38}, _}} = snapshot.disk
  end

  test "snapshot/1 returns entries for a single collector" do
    :ok = Sentinel.MetricStore.put(:system, :cpu_percent, 42.5)
    :ok = Sentinel.MetricStore.put(:disk, "/", %{percent: 38})

    system_snapshot = Sentinel.MetricStore.snapshot(:system)

    assert map_size(system_snapshot) == 1
    assert {42.5, _ts} = system_snapshot.cpu_percent
  end
end
