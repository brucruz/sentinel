defmodule Sentinel.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:sentinel, :start_on_boot, true) do
        [
          {Finch, name: Sentinel.Finch},
          Sentinel.MetricStore,
          Sentinel.Collectors.Supervisor,
          %{
            id: :startup_message,
            start: {Task, :start_link, [&startup_message/0]},
            restart: :temporary
          }
          # Milestone 3: Sentinel.Evaluator
          # Milestone 3: Sentinel.Alerting.Supervisor
          # Milestone 4: ExGram, Sentinel.Telegram.Bot
        ]
      else
        [{Finch, name: Sentinel.Finch}]
      end

    opts = [strategy: :one_for_one, name: Sentinel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp startup_message do
    Sentinel.Collectors.System.collect()
    Sentinel.Collectors.Disk.collect()

    case Sentinel.Alerting.Notifier.check_connectivity() do
      :ok ->
        text =
          Sentinel.MetricStore.snapshot()
          |> Sentinel.Telegram.Formatter.startup_message()

        case Sentinel.Alerting.Notifier.send_message(text) do
          {:ok, _} -> Logger.info("Sentinel started, Telegram notification sent")
          {:error, reason} -> Logger.warning("Startup message failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Telegram unreachable: #{inspect(reason)}")
    end
  end
end
