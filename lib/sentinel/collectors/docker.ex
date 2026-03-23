defmodule Sentinel.Collectors.Docker do
  @moduledoc """
  Collects Docker container status and resource usage via the Docker Engine API.

  Stores two types of metrics in MetricStore:
  - `:containers` — list of container summaries (name, state, image, status)
  - `{:stats, name}` — per-container CPU and memory stats
  """

  use GenServer
  @behaviour Sentinel.Collectors.Behaviour

  require Logger

  # Behaviour callbacks

  @impl Sentinel.Collectors.Behaviour
  def collect do
    GenServer.call(__MODULE__, :collect)
  end

  @impl Sentinel.Collectors.Behaviour
  def interval, do: Sentinel.Config.poll_interval(:docker)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    schedule(interval())
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call(:collect, _from, state) do
    do_collect()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:collect, state) do
    do_collect()
    schedule(interval())
    {:noreply, state}
  end

  # Private

  defp do_collect do
    case client().list_containers() do
      {:ok, raw_containers} ->
        containers = Enum.map(raw_containers, &parse_container/1)
        Sentinel.MetricStore.put(:docker, :containers, containers)

        # Collect stats for running containers
        containers
        |> Enum.filter(&(&1.state == "running"))
        |> Enum.each(fn container ->
          collect_container_stats(container.id, container.name)
        end)

      {:error, reason} ->
        Logger.warning("Docker collection failed: #{inspect(reason)}")
    end
  end

  defp collect_container_stats(id, name) do
    case client().container_stats(id) do
      {:ok, raw_stats} ->
        stats = parse_stats(raw_stats)
        Sentinel.MetricStore.put(:docker, {:stats, name}, stats)

      {:error, reason} ->
        Logger.warning("Docker stats failed for #{name}: #{inspect(reason)}")
    end
  end

  defp parse_container(raw) do
    name =
      raw
      |> Map.get("Names", ["/unknown"])
      |> List.first()
      |> String.trim_leading("/")

    %{
      id: Map.get(raw, "Id", ""),
      name: name,
      image: Map.get(raw, "Image", ""),
      state: Map.get(raw, "State", "unknown"),
      status: Map.get(raw, "Status", ""),
      created: Map.get(raw, "Created", 0)
    }
  end

  defp parse_stats(raw) do
    cpu_percent = calculate_cpu_percent(raw)
    memory = parse_memory_stats(raw)

    Map.merge(%{cpu_percent: cpu_percent}, memory)
  end

  defp calculate_cpu_percent(raw) do
    cpu = get_in(raw, ["cpu_stats", "cpu_usage", "total_usage"]) || 0
    precpu = get_in(raw, ["precpu_stats", "cpu_usage", "total_usage"]) || 0
    system_cpu = get_in(raw, ["cpu_stats", "system_cpu_usage"]) || 0
    presystem_cpu = get_in(raw, ["precpu_stats", "system_cpu_usage"]) || 0
    online_cpus = get_in(raw, ["cpu_stats", "online_cpus"]) || 1

    cpu_delta = cpu - precpu
    system_delta = system_cpu - presystem_cpu

    if system_delta > 0 and cpu_delta >= 0 do
      cpu_delta / system_delta * online_cpus * 100.0
    else
      0.0
    end
  end

  defp parse_memory_stats(raw) do
    mem_stats = Map.get(raw, "memory_stats", %{})
    usage = Map.get(mem_stats, "usage", 0)
    limit = Map.get(mem_stats, "limit", 0)
    # Subtract cache for actual working set memory
    cache = get_in(mem_stats, ["stats", "cache"]) || 0
    actual_usage = max(usage - cache, 0)

    percent = if limit > 0, do: actual_usage / limit * 100.0, else: 0.0

    %{
      memory_usage_bytes: actual_usage,
      memory_limit_bytes: limit,
      memory_percent: percent
    }
  end

  defp client do
    Application.get_env(:sentinel, :docker_client, Sentinel.Docker.Client)
  end

  defp schedule(:infinity), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :collect, ms)
end
