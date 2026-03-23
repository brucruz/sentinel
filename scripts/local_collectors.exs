# Local collectors test — exercises all collectors against your real machine.
# Works on macOS (uses Darwin backend for system metrics) and Linux.
#
# Usage: mix run --no-start scripts/local_collectors.exs

Application.ensure_all_started(:logger)
Application.ensure_all_started(:req)

Application.put_env(:sentinel, :poll_intervals, %{
  system: :infinity,
  disk: :infinity,
  docker: :infinity,
  evaluator: :infinity
})

{:ok, _} = Sentinel.MetricStore.start_link([])

IO.puts("=== Local Collectors Test ===")
IO.puts("OS: #{Sentinel.Config.os_type()}")
IO.puts("")

# --- System ---
IO.puts("--- System Metrics ---")

{:ok, _} = Sentinel.Collectors.System.start_link([])
:ok = Sentinel.Collectors.System.collect()

{cpu, _} = Sentinel.MetricStore.get(:system, :cpu_percent)
{mem, _} = Sentinel.MetricStore.get(:system, :memory)
{load, _} = Sentinel.MetricStore.get(:system, :loadavg)

IO.puts("  CPU:  #{Float.round(cpu, 1)}%")
IO.puts("  MEM:  #{Float.round(mem.percent, 1)}%  (#{div(mem.used_kb, 1024)} MB / #{div(mem.total_kb, 1024)} MB)")
IO.puts("  LOAD: #{load.load1} | #{load.load5} | #{load.load15}")
IO.puts("")

# --- Disk ---
IO.puts("--- Disk Metrics ---")

{:ok, _} = Sentinel.Collectors.Disk.start_link([])
:ok = Sentinel.Collectors.Disk.collect()

disk = Sentinel.MetricStore.snapshot(:disk)

for {mount, {entry, _ts}} <- Enum.sort_by(disk, fn {m, _} -> m end) do
  IO.puts("  #{entry.percent}%  #{mount}  (#{div(entry.used_kb, 1024)} MB / #{div(entry.total_kb, 1024)} MB)")
end

IO.puts("")

# --- Docker ---
IO.puts("--- Docker Metrics ---")
IO.puts("  Socket: #{Sentinel.Config.docker_socket()}")

{:ok, _} = Sentinel.Collectors.Docker.start_link([])
:ok = Sentinel.Collectors.Docker.collect()

case Sentinel.MetricStore.get(:docker, :containers) do
  {containers, _ts} ->
    IO.puts("  #{length(containers)} container(s):\n")

    for c <- containers do
      IO.puts("  #{c.name}  [#{c.state}]  #{c.image}")

      case Sentinel.MetricStore.get(:docker, {:stats, c.name}) do
        {stats, _ts} ->
          IO.puts("    CPU: #{Float.round(stats.cpu_percent, 2)}%")
          IO.puts("    MEM: #{Float.round(stats.memory_usage_bytes / 1_048_576, 1)} MB / #{Float.round(stats.memory_limit_bytes / 1_048_576, 1)} MB (#{Float.round(stats.memory_percent, 1)}%)")

        nil ->
          IO.puts("    (no stats)")
      end
    end

  nil ->
    IO.puts("  No containers found (is Docker running?)")
end

IO.puts("\n--- Full Snapshot ---")
snapshot = Sentinel.MetricStore.snapshot()
IO.puts("  Collectors: #{Map.keys(snapshot) |> Enum.join(", ")}")
IO.puts("\nDone!")
