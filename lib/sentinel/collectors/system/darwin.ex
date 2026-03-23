defmodule Sentinel.Collectors.System.Darwin do
  @moduledoc """
  macOS system metrics backend. Uses `top`, `vm_stat`, and `sysctl` for
  CPU, memory, and load average — equivalent to the Linux /proc reads.
  """

  @doc """
  Reads CPU usage from `top -l 1 -n 0` (one-shot, no process list).
  On macOS, top gives us user/sys/idle directly, so no delta needed.
  The `prev_raw` argument is accepted for API compatibility but ignored.
  """
  def read_cpu(_prev_raw) do
    {output, 0} = System.cmd("top", ["-l", "1", "-n", "0"])

    percent =
      output
      |> String.split("\n")
      |> Enum.find(&String.contains?(&1, "CPU usage"))
      |> parse_cpu_line()

    # No delta state needed — top gives us the instantaneous percentage
    %{percent: percent, raw: nil}
  end

  @doc """
  Reads memory from `vm_stat` (page counts) and `sysctl hw.memsize` (total bytes).
  Returns `%{total_kb, available_kb, used_kb, percent}`.
  """
  def read_memory do
    {vm_output, 0} = System.cmd("vm_stat", [])
    {mem_output, 0} = System.cmd("sysctl", ["-n", "hw.memsize"])

    total_bytes = mem_output |> String.trim() |> String.to_integer()
    total_kb = div(total_bytes, 1024)

    pages = parse_vm_stat(vm_output)
    page_size = Map.get(pages, :page_size, 16384)

    # "Available" ≈ free + inactive (pages that can be reclaimed)
    free_pages = Map.get(pages, "Pages free", 0)
    inactive_pages = Map.get(pages, "Pages inactive", 0)
    speculative_pages = Map.get(pages, "Pages speculative", 0)

    available_kb = div((free_pages + inactive_pages + speculative_pages) * page_size, 1024)
    used_kb = total_kb - available_kb
    percent = if total_kb == 0, do: 0.0, else: used_kb / total_kb * 100.0

    %{total_kb: total_kb, available_kb: available_kb, used_kb: used_kb, percent: percent}
  end

  @doc """
  Reads load averages from `sysctl -n vm.loadavg`.
  Output format: `{ 1.23 0.98 0.76 }`
  """
  def read_loadavg do
    {output, 0} = System.cmd("sysctl", ["-n", "vm.loadavg"])

    values =
      output
      |> String.trim()
      |> String.replace(~r/[{}]/, "")
      |> String.split()

    [one, five, fifteen | _] = values

    %{
      load1: parse_number(one),
      load5: parse_number(five),
      load15: parse_number(fifteen)
    }
  end

  # Private

  defp parse_cpu_line(nil), do: 0.0

  defp parse_cpu_line(line) do
    # "CPU usage: 8.63% user, 11.93% sys, 79.43% idle"
    case Regex.scan(~r/([\d.]+)%\s+(user|sys|idle)/, line) do
      matches when length(matches) >= 2 ->
        user = find_value(matches, "user")
        sys = find_value(matches, "sys")
        user + sys

      _ ->
        0.0
    end
  end

  defp find_value(matches, label) do
    case Enum.find(matches, fn [_, _val, l] -> l == label end) do
      [_, val, _] -> parse_float(val)
      nil -> 0.0
    end
  end

  defp parse_vm_stat(output) do
    lines = String.split(output, "\n", trim: true)

    # First line contains page size: "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
    page_size =
      case Regex.run(~r/page size of (\d+) bytes/, hd(lines)) do
        [_, size] -> String.to_integer(size)
        nil -> 16384
      end

    pages =
      lines
      |> Enum.drop(1)
      |> Enum.reduce(%{}, fn line, acc ->
        case Regex.run(~r/^(.+?):\s+([\d.]+)/, line) do
          [_, key, val] ->
            # vm_stat values may end with a period
            num = val |> String.trim_trailing(".") |> String.to_integer()
            Map.put(acc, String.trim(key), num)

          nil ->
            acc
        end
      end)

    Map.put(pages, :page_size, page_size)
  end

  defp parse_number(str) do
    if String.contains?(str, ".") do
      String.to_float(str)
    else
      String.to_integer(str) * 1.0
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
