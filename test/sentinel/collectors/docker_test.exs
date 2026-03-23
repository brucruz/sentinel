defmodule Sentinel.Collectors.DockerTest do
  use ExUnit.Case, async: false

  alias Sentinel.Docker.ClientMock

  setup do
    start_supervised!(Sentinel.MetricStore)
    start_supervised!(ClientMock)
    start_supervised!(Sentinel.Collectors.Docker)
    :ok
  end

  test "collect/0 stores container list in MetricStore" do
    ClientMock.set_containers(ClientMock.sample_containers())
    ClientMock.set_stats("abc123def456", ClientMock.sample_stats())
    ClientMock.set_stats("789ghi012jkl", ClientMock.sample_stats())

    :ok = Sentinel.Collectors.Docker.collect()

    {containers, _ts} = Sentinel.MetricStore.get(:docker, :containers)
    assert length(containers) == 2
    assert Enum.any?(containers, &(&1.name == "myapp-web"))
    assert Enum.any?(containers, &(&1.name == "redis"))
  end

  test "collect/0 parses container fields correctly" do
    ClientMock.set_containers(ClientMock.sample_containers())
    ClientMock.set_stats("abc123def456", ClientMock.sample_stats())
    ClientMock.set_stats("789ghi012jkl", ClientMock.sample_stats())

    :ok = Sentinel.Collectors.Docker.collect()

    {containers, _ts} = Sentinel.MetricStore.get(:docker, :containers)
    web = Enum.find(containers, &(&1.name == "myapp-web"))

    assert web.id == "abc123def456"
    assert web.image == "myapp:latest"
    assert web.state == "running"
    assert web.status == "Up 2 hours"
  end

  test "collect/0 stores stats for running containers" do
    ClientMock.set_containers(ClientMock.sample_containers())
    ClientMock.set_stats("abc123def456", ClientMock.sample_stats())
    ClientMock.set_stats("789ghi012jkl", ClientMock.sample_stats())

    :ok = Sentinel.Collectors.Docker.collect()

    {stats, _ts} = Sentinel.MetricStore.get(:docker, {:stats, "myapp-web"})
    assert stats.cpu_percent > 0
    assert stats.memory_usage_bytes > 0
    assert stats.memory_limit_bytes > 0
    assert stats.memory_percent > 0
  end

  test "collect/0 calculates CPU percent correctly" do
    # cpu_delta = 200M - 100M = 100M
    # sys_delta = 2000M - 1000M = 1000M
    # cpu% = 100M/1000M * 2 * 100 = 20.0%
    ClientMock.set_containers([hd(ClientMock.sample_containers())])
    ClientMock.set_stats("abc123def456", ClientMock.sample_stats())

    :ok = Sentinel.Collectors.Docker.collect()

    {stats, _ts} = Sentinel.MetricStore.get(:docker, {:stats, "myapp-web"})
    assert_in_delta stats.cpu_percent, 20.0, 0.1
  end

  test "collect/0 calculates memory stats correctly" do
    # usage=104857600 (100MB), cache=4194304 (4MB), limit=1073741824 (1GB)
    # actual = 100MB - 4MB = 96MB = 100663296 bytes
    # percent = 100663296 / 1073741824 * 100 ≈ 9.375%
    ClientMock.set_containers([hd(ClientMock.sample_containers())])
    ClientMock.set_stats("abc123def456", ClientMock.sample_stats())

    :ok = Sentinel.Collectors.Docker.collect()

    {stats, _ts} = Sentinel.MetricStore.get(:docker, {:stats, "myapp-web"})
    assert stats.memory_usage_bytes == 104_857_600 - 4_194_304
    assert stats.memory_limit_bytes == 1_073_741_824
    assert_in_delta stats.memory_percent, 9.375, 0.1
  end

  test "collect/0 skips stats for stopped containers" do
    ClientMock.set_containers(ClientMock.sample_containers_with_stopped())
    ClientMock.set_stats("abc123def456", ClientMock.sample_stats())

    :ok = Sentinel.Collectors.Docker.collect()

    # Running container gets stats
    assert Sentinel.MetricStore.get(:docker, {:stats, "myapp-web"}) != nil
    # Stopped container does not
    assert Sentinel.MetricStore.get(:docker, {:stats, "redis"}) == nil
  end

  test "collect/0 handles empty container list" do
    ClientMock.set_containers([])

    :ok = Sentinel.Collectors.Docker.collect()

    {containers, _ts} = Sentinel.MetricStore.get(:docker, :containers)
    assert containers == []
  end
end
