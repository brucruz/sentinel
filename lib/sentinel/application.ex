defmodule Sentinel.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Sentinel.Finch}
      # Milestone 2: Sentinel.MetricStore
      # Milestone 2: Sentinel.Collectors.Supervisor
      # Milestone 2: Sentinel.Alerting.Notifier
      # Milestone 3: Sentinel.Evaluator
      # Milestone 3: Sentinel.Alerting.Supervisor
      # Milestone 4: ExGram, Sentinel.Telegram.Bot
    ]

    opts = [strategy: :one_for_one, name: Sentinel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
