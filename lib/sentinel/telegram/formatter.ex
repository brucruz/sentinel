defmodule Sentinel.Telegram.Formatter do
  @moduledoc """
  Formats metric data into readable Telegram messages (HTML parse mode).
  """

  def startup_message(snapshot) do
    {sys_section, disk_section} = format_system_and_disk(snapshot)
    docker = Map.get(snapshot, :docker, %{})
    container_summary = format_container_summary(docker)

    """
    <b>Sentinel Started</b>

    <pre>
    #{sys_section}

    Disk
    #{disk_section}

    Containers
    #{container_summary}
    </pre>
    """
    |> dedent()
  end

  def status_message(snapshot) do
    {sys_section, disk_section} = format_system_and_disk(snapshot)
    docker = Map.get(snapshot, :docker, %{})
    container_summary = format_container_summary(docker)

    """
    <b>System Status</b>

    <pre>
    #{sys_section}

    Disk
    #{disk_section}

    Containers
    #{container_summary}
    </pre>
    """
    |> dedent()
  end

  def disk_message(disk_metrics) do
    disk_section = format_disk_entries(disk_metrics)

    """
    <b>Disk Usage</b>

    <pre>
    #{disk_section}
    </pre>
    """
    |> dedent()
  end

  def welcome_message do
    """
    <b>Sentinel</b> — VPS monitoring bot.

    I keep an eye on your server and alert you when something needs attention.

    Send /help to see available commands.
    """
    |> String.trim()
  end

  def containers_message(docker_metrics) do
    containers = get_metric_value(docker_metrics, :containers, [])

    if containers == [] do
      """
      <b>Containers</b>

      No containers found.
      """
      |> String.trim()
    else
      lines =
        containers
        |> Enum.sort_by(& &1.name)
        |> Enum.map_join("\n", fn c ->
          stats = get_metric_value(docker_metrics, {:stats, c.name}, nil)
          format_container_line(c, stats)
        end)

      """
      <b>Containers</b>

      <pre>
      #{lines}
      </pre>
      """
      |> dedent()
    end
  end

  def container_detail_message(docker_metrics, name) do
    containers = get_metric_value(docker_metrics, :containers, [])
    container = Enum.find(containers, &(&1.name == name))

    if container == nil do
      "Container <b>#{name}</b> not found.\n\nSend /containers to see available containers."
    else
      stats = get_metric_value(docker_metrics, {:stats, name}, nil)
      format_container_detail(container, stats)
    end
  end

  def help_message do
    """
    <b>Sentinel Commands</b>

    /status — Full system overview
    /disk — Disk usage per mount point
    /containers — List all containers
    /container &lt;name&gt; — Detailed stats for one container
    /peak &lt;duration&gt; — Peak CPU/MEM/SWAP over a window (e.g. 24h, 30m)
    /since &lt;timestamp&gt; — Peak CPU/MEM/SWAP since ISO 8601 timestamp
    /help — Show this message
    """
    |> String.trim()
  end

  def peak_message(label, nil) do
    """
    <b>Peak — #{label}</b>

    No samples in range yet.
    """
    |> String.trim()
  end

  def peak_message(label, %{cpu: cpu, mem: mem, swap: swap, load1: load1}) do
    lines = [
      "CPU   #{pad_left("#{Float.round(cpu.value * 1.0, 1)}%", 6)}  at #{format_ts(cpu.ts)}",
      "MEM   #{pad_left("#{Float.round(mem.value * 1.0, 1)}%", 6)}  at #{format_ts(mem.ts)}",
      "SWAP  #{pad_left("#{Float.round(swap.value * 1.0, 1)}%", 6)}  at #{format_ts(swap.ts)}",
      "LOAD  #{pad_left(Float.to_string(Float.round(load1.value * 1.0, 2)), 6)}  at #{format_ts(load1.ts)}"
    ]

    """
    <b>Peak — #{label}</b>

    <pre>
    #{Enum.join(lines, "\n")}
    </pre>
    """
    |> dedent()
  end

  defp format_ts(nil), do: "-"

  defp format_ts(ts) when is_integer(ts) do
    ts |> DateTime.from_unix!() |> DateTime.to_iso8601()
  end

  def alert_message(severity, details) do
    label = severity |> to_string() |> String.upcase()

    """
    <b>[#{label}] Alert</b>

    #{details}
    """
    |> String.trim()
  end

  # Shared formatting

  defp format_system_and_disk(snapshot) do
    sys = Map.get(snapshot, :system, %{})
    disk = Map.get(snapshot, :disk, %{})

    sys_section = format_system(sys)
    disk_section = format_disk_entries(disk)

    {sys_section, disk_section}
  end

  defp format_system(sys) do
    cpu = get_metric_value(sys, :cpu_percent, 0.0)
    mem = get_metric_value(sys, :memory, %{percent: 0.0, used_kb: 0, total_kb: 0})
    load = get_metric_value(sys, :loadavg, %{load1: 0.0, load5: 0.0, load15: 0.0})

    """
    CPU   #{pad_left("#{Float.round(cpu * 1.0, 1)}%", 6)}
    MEM   #{pad_left("#{Float.round(mem.percent * 1.0, 1)}%", 6)}  #{format_kb(mem.used_kb)} / #{format_kb(mem.total_kb)}
    LOAD  #{load.load1} | #{load.load5} | #{load.load15}  (1m|5m|15m)
    """
    |> String.trim()
  end

  defp format_disk_entries(disk) do
    entries =
      disk
      |> Enum.map(fn {_mount, {entry, _ts}} -> entry end)
      |> Enum.filter(&primary_mount?/1)
      |> Enum.sort_by(& &1.mount)

    if entries == [] do
      "No disks found"
    else
      Enum.map_join(entries, "\n", fn e ->
        bar = progress_bar(e.percent)
        name = truncate(e.mount, 12)
        size = "#{format_kb(e.used_kb)}/#{format_kb(e.total_kb)}"
        "#{bar} #{pad_right("#{e.percent}%", 4)} #{pad_right(name, 12)} #{size}"
      end)
    end
  end

  defp format_container_summary(docker) do
    containers = get_metric_value(docker, :containers, [])

    if containers == [] do
      "No containers found"
    else
      running = Enum.count(containers, &(&1.state == "running"))
      total = length(containers)
      stopped = total - running

      summary = "#{running} running"
      summary = if stopped > 0, do: summary <> ", #{stopped} stopped", else: summary
      summary
    end
  end

  defp format_container_line(container, stats) do
    icon = if container.state == "running", do: "●", else: "○"

    if stats do
      cpu = Float.round(stats.cpu_percent, 1)
      mem = format_bytes(stats.memory_usage_bytes)
      "#{icon} #{container.name}\n  #{container.state} · CPU #{cpu}% · MEM #{mem}"
    else
      "#{icon} #{container.name}\n  #{container.state}"
    end
  end

  defp format_container_detail(container, stats) do
    status_line = "State:   #{container.state}"
    status_line2 = "Status:  #{container.status}"
    image_line = "Image:   #{container.image}"

    stats_section =
      if stats do
        cpu = Float.round(stats.cpu_percent, 1)
        mem_used = format_bytes(stats.memory_usage_bytes)
        mem_limit = format_bytes(stats.memory_limit_bytes)
        mem_pct = Float.round(stats.memory_percent, 1)

        """
        CPU:     #{cpu}%
        Memory:  #{mem_used} / #{mem_limit} (#{mem_pct}%)
        """
        |> String.trim()
      else
        "Stats:   not available (container not running)"
      end

    """
    <b>Container: #{container.name}</b>

    <pre>
    #{status_line}
    #{status_line2}
    #{image_line}
    #{stats_section}
    </pre>
    """
    |> dedent()
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp dedent(text) do
    text
    |> String.replace(~r/^    /m, "")
    |> String.trim()
  end

  # Helpers

  defp primary_mount?(entry) do
    mount = entry.mount

    cond do
      mount == "/" -> true
      String.starts_with?(mount, "/System/") -> false
      String.starts_with?(mount, "/Library/") -> false
      String.starts_with?(mount, "/private/") -> false
      String.starts_with?(mount, "/snap/") -> false
      length(Path.split(mount)) <= 3 -> true
      true -> false
    end
  end

  defp progress_bar(percent) do
    filled = round(percent / 10)
    empty = 10 - filled
    "[#{String.duplicate("#", filled)}#{String.duplicate("-", empty)}]"
  end

  defp truncate(str, max_len) do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len - 1) <> "~"
    else
      str
    end
  end

  defp pad_right(str, len) do
    str = to_string(str)
    pad = max(len - String.length(str), 0)
    str <> String.duplicate(" ", pad)
  end

  defp pad_left(str, len) do
    str = to_string(str)
    pad = max(len - String.length(str), 0)
    String.duplicate(" ", pad) <> str
  end

  defp get_metric_value(metrics, key, default) do
    case Map.get(metrics, key) do
      {value, _timestamp} -> value
      nil -> default
    end
  end

  defp format_kb(kb) when kb >= 1_048_576, do: "#{Float.round(kb / 1_048_576, 1)} GB"
  defp format_kb(kb) when kb >= 1_024, do: "#{Float.round(kb / 1_024, 1)} MB"
  defp format_kb(kb), do: "#{kb} KB"
end
