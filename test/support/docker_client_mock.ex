defmodule Sentinel.Docker.ClientMock do
  @moduledoc """
  Mock Docker client for tests. Returns data from an Agent process.
  Start the agent and populate with `set_containers/1` and `set_stats/2` before use.
  """

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{containers: [], stats: %{}} end, name: __MODULE__)
  end

  def set_containers(containers) do
    Agent.update(__MODULE__, &Map.put(&1, :containers, containers))
  end

  def set_stats(container_id, stats) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:stats, container_id], stats)
    end)
  end

  # Docker.Client API

  def list_containers do
    containers = Agent.get(__MODULE__, & &1.containers)
    {:ok, containers}
  end

  def container_stats(container_id) do
    stats = Agent.get(__MODULE__, &get_in(&1, [:stats, container_id]))

    case stats do
      nil -> {:error, :not_found}
      data -> {:ok, data}
    end
  end

  # Test fixtures

  def sample_containers do
    [
      %{
        "Id" => "abc123def456",
        "Names" => ["/myapp-web"],
        "Image" => "myapp:latest",
        "State" => "running",
        "Status" => "Up 2 hours",
        "Created" => 1_700_000_000
      },
      %{
        "Id" => "789ghi012jkl",
        "Names" => ["/redis"],
        "Image" => "redis:7-alpine",
        "State" => "running",
        "Status" => "Up 2 hours",
        "Created" => 1_700_000_000
      }
    ]
  end

  def sample_containers_with_stopped do
    [
      %{
        "Id" => "abc123def456",
        "Names" => ["/myapp-web"],
        "Image" => "myapp:latest",
        "State" => "running",
        "Status" => "Up 2 hours",
        "Created" => 1_700_000_000
      },
      %{
        "Id" => "789ghi012jkl",
        "Names" => ["/redis"],
        "Image" => "redis:7-alpine",
        "State" => "exited",
        "Status" => "Exited (1) 5 minutes ago",
        "Created" => 1_700_000_000
      }
    ]
  end

  def sample_stats do
    %{
      "cpu_stats" => %{
        "cpu_usage" => %{"total_usage" => 200_000_000},
        "system_cpu_usage" => 2_000_000_000,
        "online_cpus" => 2
      },
      "precpu_stats" => %{
        "cpu_usage" => %{"total_usage" => 100_000_000},
        "system_cpu_usage" => 1_000_000_000
      },
      "memory_stats" => %{
        "usage" => 104_857_600,
        "limit" => 1_073_741_824,
        "stats" => %{"cache" => 4_194_304}
      }
    }
  end
end
