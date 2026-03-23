defmodule Sentinel.Alerting.Cooldown do
  @moduledoc """
  Tracks when alerts were last fired to prevent spam.

  An alert key won't re-fire within the configured cooldown window.
  Uses a public ETS table for lock-free reads from the Evaluator.
  """

  use GenServer

  @table :sentinel_cooldowns

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if enough time has passed since the last alert for this key.
  """
  def can_alert?(alert_key) do
    case :ets.lookup(@table, alert_key) do
      [{_, last_fired}] ->
        now = System.system_time(:second)
        cooldown_seconds = Sentinel.Config.cooldown_minutes() * 60
        now - last_fired >= cooldown_seconds

      [] ->
        true
    end
  end

  @doc """
  Records that an alert was just fired for this key.
  """
  def record_alert(alert_key) do
    :ets.insert(@table, {alert_key, System.system_time(:second)})
    :ok
  end

  @doc """
  Clears all cooldown records. Useful for testing or manual reset.
  """
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, table}
  end
end
