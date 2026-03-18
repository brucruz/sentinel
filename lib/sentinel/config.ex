defmodule Sentinel.Config do
  @moduledoc """
  Runtime configuration helpers.

  Reads from application env with sensible defaults.
  """

  def telegram_bot_token, do: Application.fetch_env!(:sentinel, :telegram_bot_token)
  def telegram_chat_id, do: Application.fetch_env!(:sentinel, :telegram_chat_id)
  def docker_socket, do: Application.get_env(:sentinel, :docker_socket, "/var/run/docker.sock")
  def cooldown_minutes, do: Application.get_env(:sentinel, :cooldown_minutes, 15)

  def poll_interval(collector) do
    defaults = %{
      system: :timer.seconds(10),
      disk: :timer.seconds(60),
      docker: :timer.seconds(15),
      evaluator: :timer.seconds(30)
    }

    :sentinel
    |> Application.get_env(:poll_intervals, %{})
    |> Map.get(collector, Map.fetch!(defaults, collector))
  end

  def thresholds do
    Application.get_env(:sentinel, :thresholds, [])
  end
end
