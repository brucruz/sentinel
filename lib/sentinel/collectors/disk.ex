defmodule Sentinel.Collectors.Disk do
  @moduledoc """
  Collects disk usage per mount point.
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
  def interval, do: Sentinel.Config.poll_interval(:disk)

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
    entries = run_df() |> parse_df()

    Enum.each(entries, fn entry ->
      Sentinel.MetricStore.put(:disk, entry.mount, entry)
    end)
  end

  defp run_df do
    {output, 0} = System.cmd("df", ["-Pk"])
    output
  end

  @doc false
  def parse_df(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.map(&parse_df_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn entry ->
      String.starts_with?(entry.filesystem, "/") and String.starts_with?(entry.mount, "/")
    end)
  end

  defp parse_df_line(line) do
    case String.split(line) do
      [fs, total_str, used_str, avail_str, percent_str, mount] ->
        %{
          filesystem: fs,
          total_kb: String.to_integer(total_str),
          used_kb: String.to_integer(used_str),
          available_kb: String.to_integer(avail_str),
          percent: percent_str |> String.trim_trailing("%") |> String.to_integer(),
          mount: mount
        }

      _ ->
        nil
    end
  end

  defp schedule(:infinity), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :collect, ms)
end
