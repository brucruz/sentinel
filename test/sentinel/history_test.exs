defmodule Sentinel.HistoryTest do
  use ExUnit.Case, async: false

  alias Sentinel.History

  setup do
    start_supervised!(History)
    :ok
  end

  test "put/5 stores a row and size reflects it" do
    assert History.size() == 0
    :ok = History.put(10.0, 20.0, 0.0, 0.5, 1_700_000_000)
    assert History.size() == 1
  end

  test "peak_since/1 returns nil when no samples" do
    assert History.peak_since(0) == nil
  end

  test "peak_since/1 picks the max value and its timestamp per metric" do
    :ok = History.put(10.0, 20.0, 5.0, 0.3, 1_700_000_000)
    :ok = History.put(80.0, 30.0, 2.0, 0.9, 1_700_000_010)
    :ok = History.put(40.0, 95.0, 50.0, 0.5, 1_700_000_020)

    %{cpu: cpu, mem: mem, swap: swap, load1: load1} = History.peak_since(1_700_000_000)

    assert cpu.value == 80.0
    assert cpu.ts == 1_700_000_010
    assert mem.value == 95.0
    assert mem.ts == 1_700_000_020
    assert swap.value == 50.0
    assert swap.ts == 1_700_000_020
    assert load1.value == 0.9
    assert load1.ts == 1_700_000_010
  end

  test "peak_since/1 ignores samples older than the cutoff" do
    :ok = History.put(99.0, 0.0, 0.0, 0.0, 1_700_000_000)
    :ok = History.put(10.0, 0.0, 0.0, 0.0, 1_700_000_100)

    %{cpu: cpu} = History.peak_since(1_700_000_050)
    assert cpu.value == 10.0
    assert cpu.ts == 1_700_000_100
  end

  test "put/5 evicts rows older than 24h on write" do
    now = System.system_time(:second)
    day = 24 * 60 * 60

    # Old sample, then a new one — old should be evicted by the new put.
    :ok = History.put(50.0, 50.0, 50.0, 1.0, now - day - 60)
    assert History.size() == 1
    :ok = History.put(10.0, 10.0, 10.0, 0.1, now)
    assert History.size() == 1

    %{cpu: cpu} = History.peak_since(now - day)
    assert cpu.value == 10.0
  end

  test "peak_over/1 uses trailing window from now" do
    now = System.system_time(:second)
    :ok = History.put(50.0, 50.0, 50.0, 1.0, now - 30)
    :ok = History.put(75.0, 25.0, 10.0, 0.5, now - 5)

    %{cpu: cpu} = History.peak_over(60)
    assert cpu.value == 75.0
  end
end
