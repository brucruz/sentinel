defmodule Sentinel.Telegram.Formatter do
  @moduledoc """
  Formats metric data into readable Telegram messages (HTML parse mode).
  """

  def startup_message(snapshot) do
    sys = Map.get(snapshot, :system, %{})
    disk = Map.get(snapshot, :disk, %{})

    cpu = get_metric_value(sys, :cpu_percent, 0.0)
    mem = get_metric_value(sys, :memory, %{percent: 0.0, used_kb: 0, total_kb: 0})
    load = get_metric_value(sys, :loadavg, %{load1: 0.0, load5: 0.0, load15: 0.0})

    disk_entries =
      disk
      |> Enum.map(fn {_mount, {entry, _ts}} -> entry end)
      |> Enum.filter(&primary_mount?/1)
      |> Enum.sort_by(& &1.mount)

    disk_lines =
      Enum.map_join(disk_entries, "\n", fn e ->
        bar = progress_bar(e.percent)

        "#{bar} #{pad_right("#{e.percent}%", 4)}  #{pad_right(e.mount, 10)}  #{format_kb(e.used_kb)}/#{format_kb(e.total_kb)}"
      end)

    disk_section = if disk_lines == "", do: "No disks found", else: disk_lines

    """
    <b>Sentinel Started</b>

    <pre>
    CPU   #{pad_left("#{Float.round(cpu * 1.0, 1)}%", 6)}
    MEM   #{pad_left("#{Float.round(mem.percent * 1.0, 1)}%", 6)}  #{format_kb(mem.used_kb)} / #{format_kb(mem.total_kb)}
    LOAD  #{load.load1} | #{load.load5} | #{load.load15}  (1m|5m|15m)

    Disk
    #{disk_section}
    </pre>
    """
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
