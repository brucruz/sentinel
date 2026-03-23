defmodule Sentinel.Alerting.Supervisor do
  @moduledoc """
  Supervises the alerting subsystem: cooldown tracking and notification delivery.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Sentinel.Alerting.Cooldown
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
