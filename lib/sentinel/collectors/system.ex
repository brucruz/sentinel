defmodule Sentinel.Collectors.System do
  @moduledoc """
  Collects CPU, memory, and load average metrics.

  Delegates to a platform-specific backend:
  - `System.Linux` reads from /proc (production on VPS)
  - `System.Darwin` uses sysctl/vm_stat/top (local dev on macOS)

  The backend is selected automatically at init based on `:os.type()`,
  or can be overridden via config `:system_backend` (useful for tests).
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
    backend = Application.get_env(:sentinel, :system_backend, default_backend())

    state = %{
      prev_cpu: nil,
      backend: backend
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
    backend = state.backend

    cpu_reading = backend.read_cpu(state.prev_cpu)
    memory = backend.read_memory()
    loadavg = backend.read_loadavg()

    Sentinel.MetricStore.put(:system, :cpu_percent, cpu_reading.percent)
    Sentinel.MetricStore.put(:system, :memory, memory)
    Sentinel.MetricStore.put(:system, :loadavg, loadavg)

    Sentinel.History.put(
      cpu_reading.percent,
      memory.percent,
      memory.swap_percent,
      loadavg.load1
    )

    %{state | prev_cpu: cpu_reading.raw}
  end

  defp default_backend do
    case Sentinel.Config.os_type() do
      :macos -> Sentinel.Collectors.System.Darwin
      _ -> Sentinel.Collectors.System.Linux
    end
  end

  defp schedule(:infinity), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :collect, ms)
end
