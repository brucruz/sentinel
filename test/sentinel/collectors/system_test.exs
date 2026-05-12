defmodule Sentinel.Collectors.SystemTest do
  use ExUnit.Case, async: false

  setup do
    store = start_supervised!(Sentinel.MetricStore)
    _history = start_supervised!(Sentinel.History)
    collector = start_supervised!(Sentinel.Collectors.System)
    %{store: store, collector: collector}
  end

  test "collect/0 writes cpu_percent, memory, and loadavg to MetricStore" do
    :ok = Sentinel.Collectors.System.collect()

    assert Sentinel.MetricStore.get(:system, :cpu_percent) != nil
    assert Sentinel.MetricStore.get(:system, :memory) != nil
    assert Sentinel.MetricStore.get(:system, :loadavg) != nil
  end

  test "first collect reports 0.0% CPU (no previous reading)" do
    :ok = Sentinel.Collectors.System.collect()

    {cpu, _ts} = Sentinel.MetricStore.get(:system, :cpu_percent)
    assert cpu == 0.0
  end

  test "memory values match fixture" do
    # Fixture: MemTotal=8052444, MemAvailable=4020000
    # used = 8052444 - 4020000 = 4032444
    # percent = 4032444 / 8052444 * 100 ≈ 50.08%
    :ok = Sentinel.Collectors.System.collect()

    {memory, _ts} = Sentinel.MetricStore.get(:system, :memory)
    assert memory.total_kb == 8_052_444
    assert memory.available_kb == 4_020_000
    assert memory.used_kb == 4_032_444
    assert_in_delta memory.percent, 50.08, 0.1
  end

  test "memory includes swap fields from fixture" do
    # Fixture: SwapTotal=2097148, SwapFree=2097148 -> swap_used=0, swap_percent=0.0
    :ok = Sentinel.Collectors.System.collect()

    {memory, _ts} = Sentinel.MetricStore.get(:system, :memory)
    assert memory.swap_total_kb == 2_097_148
    assert memory.swap_free_kb == 2_097_148
    assert memory.swap_used_kb == 0
    assert memory.swap_percent == 0.0
  end

  test "loadavg values match fixture" do
    # Fixture: 0.52 0.34 0.28
    :ok = Sentinel.Collectors.System.collect()

    {loadavg, _ts} = Sentinel.MetricStore.get(:system, :loadavg)
    assert loadavg.load1 == 0.52
    assert loadavg.load5 == 0.34
    assert loadavg.load15 == 0.28
  end
end
