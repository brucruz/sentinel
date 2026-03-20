defmodule Sentinel.Collectors.System do
  @moduledoc """
  Collects CPU, memory, and load average from /proc.
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
  def interval, do: Sentinel.Config.poll_interval(:system)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    state = %{
      prev_cpu: nil,
      proc_base: Sentinel.Config.proc_base_path()
    }

    schedule(interval())
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:collect, _from, state) do
    new_state = do_collect(state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:collect, state) do
    new_state = do_collect(state)
    schedule(interval())
    {:noreply, new_state}
  end

  # Private

  defp do_collect(state) do
    cpu_reading = read_cpu(state.proc_base)
    cpu_percent = calc_cpu_percent(state.prev_cpu, cpu_reading)
    memory = read_memory(state.proc_base)
    loadavg = read_loadavg(state.proc_base)

    Sentinel.MetricStore.put(:system, :cpu_percent, cpu_percent)
    Sentinel.MetricStore.put(:system, :memory, memory)
    Sentinel.MetricStore.put(:system, :loadavg, loadavg)

    %{state | prev_cpu: cpu_reading}
  end

  defp read_cpu(proc_base) do
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

  defp read_memory(proc_base) do
    path = Path.join(proc_base, "meminfo")
    values = path |> File.read!() |> parse_meminfo()

    total = Map.fetch!(values, "MemTotal")
    available = Map.fetch!(values, "MemAvailable")
    used = total - available
    percent = if total == 0, do: 0.0, else: used / total * 100.0

    %{total_kb: total, available_kb: available, used_kb: used, percent: percent}
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

  defp read_loadavg(proc_base) do
    path = Path.join(proc_base, "loadavg")
    [one, five, fifteen | _] = path |> File.read!() |> String.split()

    %{
      load1: String.to_float(one),
      load5: String.to_float(five),
      load15: String.to_float(fifteen)
    }
  end

  defp schedule(:infinity), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :collect, ms)
end
