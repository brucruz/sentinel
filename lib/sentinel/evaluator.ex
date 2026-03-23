defmodule Sentinel.Evaluator do
  @moduledoc """
  Periodically reads metrics from MetricStore and compares against
  configured thresholds, emitting alert events when crossed.

  Threshold formats:
  - `{:system, :cpu_percent, :gt, 90, :warning}`
  - `{:system, :memory_percent, :gt, 85, :warning}`
  - `{:disk, "/", :gt, 80, :warning}` (checks used percent)
  - `{:docker, :container_stopped, :any, nil, :critical}`
  """

  use GenServer

  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs a single evaluation cycle. Useful for testing.
  """
  def evaluate do
    GenServer.call(__MODULE__, :evaluate)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    schedule(interval())
    {:ok, %{}}
  end

  @impl true
  def handle_call(:evaluate, _from, state) do
    alerts = do_evaluate()
    {:reply, alerts, state}
  end

  @impl true
  def handle_info(:evaluate, state) do
    do_evaluate()
    schedule(interval())
    {:noreply, state}
  end

  # Evaluation logic

  defp do_evaluate do
    snapshot = Sentinel.MetricStore.snapshot()
    thresholds = Sentinel.Config.thresholds()

    alerts =
      thresholds
      |> Enum.flat_map(&check_threshold(&1, snapshot))
      |> Enum.filter(&cooldown_allows?/1)

    Enum.each(alerts, &fire_alert/1)

    alerts
  end

  @doc false
  def check_threshold({:system, :cpu_percent, op, value, severity}, snapshot) do
    cpu = get_system_metric(snapshot, :cpu_percent, 0.0)

    if compare(cpu, op, value) do
      [%{key: {:system, :cpu_percent}, severity: severity,
         message: "CPU at #{Float.round(cpu, 1)}% (threshold: #{value}%)"}]
    else
      []
    end
  end

  def check_threshold({:system, :memory_percent, op, value, severity}, snapshot) do
    mem = get_system_metric(snapshot, :memory, %{percent: 0.0})
    percent = mem.percent

    if compare(percent, op, value) do
      [%{key: {:system, :memory_percent}, severity: severity,
         message: "Memory at #{Float.round(percent, 1)}% (threshold: #{value}%)"}]
    else
      []
    end
  end

  def check_threshold({:disk, mount, op, value, severity}, snapshot) do
    disk = Map.get(snapshot, :disk, %{})

    case Map.get(disk, mount) do
      {entry, _ts} ->
        if compare(entry.percent, op, value) do
          [%{key: {:disk, mount, value}, severity: severity,
             message: "Disk #{mount} at #{entry.percent}% (threshold: #{value}%)"}]
        else
          []
        end

      nil ->
        []
    end
  end

  def check_threshold({:docker, :container_stopped, :any, _value, severity}, snapshot) do
    docker = Map.get(snapshot, :docker, %{})

    case Map.get(docker, :containers) do
      {containers, _ts} when is_list(containers) ->
        running_prefixes =
          containers
          |> Enum.filter(&(&1.state == "running"))
          |> MapSet.new(&service_prefix(&1.name))

        containers
        |> Enum.reject(&(&1.state == "running"))
        |> Enum.reject(&MapSet.member?(running_prefixes, service_prefix(&1.name)))
        |> Enum.map(fn c ->
          %{key: {:docker, :container_stopped, c.name}, severity: severity,
            message: "Container <b>#{c.name}</b> is #{c.state} (#{c.status})"}
        end)

      _ ->
        []
    end
  end

  def check_threshold(rule, _snapshot) do
    Logger.warning("Unknown threshold rule: #{inspect(rule)}")
    []
  end

  defp get_system_metric(snapshot, metric, default) do
    sys = Map.get(snapshot, :system, %{})

    case Map.get(sys, metric) do
      {value, _ts} -> value
      nil -> default
    end
  end

  defp compare(actual, :gt, threshold), do: actual > threshold
  defp compare(actual, :gte, threshold), do: actual >= threshold
  defp compare(actual, :lt, threshold), do: actual < threshold
  defp compare(actual, :lte, threshold), do: actual <= threshold

  defp cooldown_allows?(%{key: key}) do
    Sentinel.Alerting.Cooldown.can_alert?(key)
  end

  defp fire_alert(%{key: key, severity: severity, message: message}) do
    text = Sentinel.Telegram.Formatter.alert_message(severity, message)

    case Sentinel.Alerting.Notifier.send_message(text) do
      {:ok, _} ->
        Sentinel.Alerting.Cooldown.record_alert(key)
        Logger.info("Alert fired: #{inspect(key)}")

      {:error, reason} ->
        Logger.warning("Failed to send alert #{inspect(key)}: #{inspect(reason)}")
    end
  end

  defp interval, do: Sentinel.Config.poll_interval(:evaluator)

  # Strips trailing hex hash (12+ chars) from container names to get the service prefix.
  # e.g., "global_dial-web-82200684be7ccd32f9de..." → "global_dial-web"
  # Non-matching names (e.g., "redis") are returned as-is.
  defp service_prefix(name) do
    case Regex.run(~r/^(.+)-[0-9a-f]{12,}$/, name) do
      [_, prefix] -> prefix
      nil -> name
    end
  end

  defp schedule(:infinity), do: :ok
  defp schedule(ms), do: Process.send_after(self(), :evaluate, ms)
end
