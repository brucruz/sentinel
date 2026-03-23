# Local Docker test — exercises the Docker client and collector against your real Docker.
# Skips /proc-dependent collectors (won't work on macOS).
#
# Usage: mix run --no-start scripts/local_docker.exs
#
# Pass the socket path as an argument if it's not at the default location:
#   DOCKER_SOCKET=~/.docker/run/docker.sock mix run --no-start scripts/local_docker.exs

Application.ensure_all_started(:logger)
Application.ensure_all_started(:req)

socket =
  System.get_env("DOCKER_SOCKET") ||
    Path.expand("~/.docker/run/docker.sock")

IO.puts("=== Docker Client Test ===")
IO.puts("Socket: #{socket}")
IO.puts("")

# 1. Test Docker.Client.list_containers directly via Req
IO.puts("--- list_containers ---")

case Req.get("http://localhost/v1.45/containers/json?all=true",
       unix_socket: socket,
       receive_timeout: 5_000
     ) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("OK — #{length(body)} container(s) found\n")

    for c <- body do
      name = c["Names"] |> List.first() |> String.trim_leading("/")
      IO.puts("  #{name}  state=#{c["State"]}  image=#{c["Image"]}")
    end

  {:ok, %{status: status, body: body}} ->
    IO.puts("ERROR — HTTP #{status}: #{inspect(body)}")

  {:error, reason} ->
    IO.puts("ERROR — #{inspect(reason)}")
    IO.puts("\nHint: check socket path. Try: DOCKER_SOCKET=/var/run/docker.sock")
    System.halt(1)
end

IO.puts("")

# 2. Test container stats for running containers
IO.puts("--- container_stats ---")

case Req.get("http://localhost/v1.45/containers/json",
       unix_socket: socket,
       receive_timeout: 5_000
     ) do
  {:ok, %{status: 200, body: running}} ->
    for c <- Enum.take(running, 3) do
      id = c["Id"]
      name = c["Names"] |> List.first() |> String.trim_leading("/")

      case Req.get("http://localhost/v1.45/containers/#{id}/stats?stream=false",
             unix_socket: socket,
             receive_timeout: 10_000
           ) do
        {:ok, %{status: 200, body: stats}} ->
          cpu = get_in(stats, ["cpu_stats", "cpu_usage", "total_usage"]) || 0
          precpu = get_in(stats, ["precpu_stats", "cpu_usage", "total_usage"]) || 0
          sys = get_in(stats, ["cpu_stats", "system_cpu_usage"]) || 0
          presys = get_in(stats, ["precpu_stats", "system_cpu_usage"]) || 0
          cpus = get_in(stats, ["cpu_stats", "online_cpus"]) || 1

          cpu_pct =
            if sys - presys > 0,
              do: (cpu - precpu) / (sys - presys) * cpus * 100.0,
              else: 0.0

          mem_usage = get_in(stats, ["memory_stats", "usage"]) || 0
          mem_limit = get_in(stats, ["memory_stats", "limit"]) || 0
          cache = get_in(stats, ["memory_stats", "stats", "cache"]) || 0
          actual_mem = max(mem_usage - cache, 0)
          mem_pct = if mem_limit > 0, do: actual_mem / mem_limit * 100.0, else: 0.0

          IO.puts("  #{name}:")
          IO.puts("    CPU:  #{Float.round(cpu_pct, 2)}%")
          IO.puts("    MEM:  #{Float.round(actual_mem / 1_048_576, 1)} MB / #{Float.round(mem_limit / 1_048_576, 1)} MB (#{Float.round(mem_pct, 1)}%)")

        {:ok, %{status: status}} ->
          IO.puts("  #{name}: stats error HTTP #{status}")

        {:error, reason} ->
          IO.puts("  #{name}: stats error #{inspect(reason)}")
      end
    end

  _ ->
    IO.puts("Skipped (no running containers)")
end

IO.puts("")

# 3. Test through the actual Sentinel modules
IO.puts("--- Sentinel.Docker.Client module ---")
Application.put_env(:sentinel, :docker_socket, socket)

case Sentinel.Docker.Client.list_containers() do
  {:ok, containers} ->
    IO.puts("OK — #{length(containers)} container(s)")

  {:error, reason} ->
    IO.puts("ERROR — #{inspect(reason)}")
end

IO.puts("")

# 4. Test the full collector flow
IO.puts("--- Sentinel.Collectors.Docker (full flow) ---")
Application.put_env(:sentinel, :poll_intervals, %{docker: :infinity})

{:ok, _} = Sentinel.MetricStore.start_link([])
{:ok, _} = Sentinel.Collectors.Docker.start_link([])

:ok = Sentinel.Collectors.Docker.collect()

case Sentinel.MetricStore.get(:docker, :containers) do
  {containers, _ts} ->
    IO.puts("Stored #{length(containers)} container(s) in MetricStore:")

    for c <- containers do
      IO.puts("  #{c.name}  state=#{c.state}  image=#{c.image}")

      case Sentinel.MetricStore.get(:docker, {:stats, c.name}) do
        {stats, _ts} ->
          IO.puts("    CPU: #{Float.round(stats.cpu_percent, 2)}%")
          IO.puts("    MEM: #{Float.round(stats.memory_usage_bytes / 1_048_576, 1)} MB / #{Float.round(stats.memory_limit_bytes / 1_048_576, 1)} MB (#{Float.round(stats.memory_percent, 1)}%)")

        nil ->
          IO.puts("    (no stats — container not running)")
      end
    end

  nil ->
    IO.puts("ERROR — no containers stored in MetricStore")
end

IO.puts("\nDone!")
