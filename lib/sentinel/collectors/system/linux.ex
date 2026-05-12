defmodule Sentinel.Collectors.System.Linux do
  @moduledoc """
  Linux system metrics backend. Reads from /proc/stat, /proc/meminfo, /proc/loadavg.
  """

  @doc """
  Reads CPU times from /proc/stat and computes usage percent as a delta
  from the previous reading. Returns `%{percent: float, raw: term}`.
  """
  def read_cpu(prev_raw) do
    proc_base = Sentinel.Config.proc_base_path()
    current = read_cpu_times(proc_base)
    percent = calc_cpu_percent(prev_raw, current)
    %{percent: percent, raw: current}
  end

  @doc """
  Reads memory info from /proc/meminfo.
  Returns `%{total_kb, available_kb, used_kb, percent, swap_total_kb,
  swap_free_kb, swap_used_kb, swap_percent}`.
  """
  def read_memory do
    proc_base = Sentinel.Config.proc_base_path()
    path = Path.join(proc_base, "meminfo")
    values = path |> File.read!() |> parse_meminfo()

    total = Map.fetch!(values, "MemTotal")
    available = Map.fetch!(values, "MemAvailable")
    used = total - available
    percent = if total == 0, do: 0.0, else: used / total * 100.0

    swap_total = Map.get(values, "SwapTotal", 0)
    swap_free = Map.get(values, "SwapFree", 0)
    swap_used = swap_total - swap_free
    swap_percent = if swap_total == 0, do: 0.0, else: swap_used / swap_total * 100.0

    %{
      total_kb: total,
      available_kb: available,
      used_kb: used,
      percent: percent,
      swap_total_kb: swap_total,
      swap_free_kb: swap_free,
      swap_used_kb: swap_used,
      swap_percent: swap_percent
    }
  end

  @doc """
  Reads load averages from /proc/loadavg.
  Returns `%{load1, load5, load15}`.
  """
  def read_loadavg do
    proc_base = Sentinel.Config.proc_base_path()
    path = Path.join(proc_base, "loadavg")
    [one, five, fifteen | _] = path |> File.read!() |> String.split()

    %{
      load1: String.to_float(one),
      load5: String.to_float(five),
      load15: String.to_float(fifteen)
    }
  end

  # Private

  defp read_cpu_times(proc_base) do
    path = Path.join(proc_base, "stat")
    [cpu_line | _] = path |> File.read!() |> String.split("\n")
    ["cpu" | values] = String.split(cpu_line)
    numbers = Enum.map(values, &String.to_integer/1)
    idle = Enum.at(numbers, 3) + Enum.at(numbers, 4)
    total = Enum.sum(numbers)
    {idle, total}
  end

  defp calc_cpu_percent(nil, _current), do: 0.0

  defp calc_cpu_percent({prev_idle, prev_total}, {curr_idle, curr_total}) do
    delta_total = curr_total - prev_total
    delta_idle = curr_idle - prev_idle

    if delta_total == 0,
      do: 0.0,
      else: (1.0 - delta_idle / delta_total) * 100.0
  end

  defp parse_meminfo(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ~r/:\s+/) do
        [key, rest] ->
          value = rest |> String.split() |> List.first() |> String.to_integer()
          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end
end
