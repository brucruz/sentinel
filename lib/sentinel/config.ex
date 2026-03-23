defmodule Sentinel.Config do
  @moduledoc """
  Runtime configuration helpers.

  Reads from application env with sensible defaults.
  """

  def telegram_bot_token, do: Application.fetch_env!(:sentinel, :telegram_bot_token)
  def telegram_chat_id, do: Application.fetch_env!(:sentinel, :telegram_chat_id)
  def docker_socket do
    Application.get_env(:sentinel, :docker_socket, nil) || detect_docker_socket()
  end

  defp detect_docker_socket do
    candidates = [
      "/var/run/docker.sock",
      Path.expand("~/.docker/run/docker.sock")
    ]

    Enum.find(candidates, "/var/run/docker.sock", &File.exists?/1)
  end

  def os_type do
    case :os.type() do
      {:unix, :darwin} -> :macos
      {:unix, _} -> :linux
      other -> other
    end
  end
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

  def proc_base_path, do: Application.get_env(:sentinel, :proc_base_path, "/proc")

  def thresholds do
    Application.get_env(:sentinel, :thresholds, default_thresholds())
  end

  defp default_thresholds do
    [
      {:system, :cpu_percent, :gt, 90, :warning},
      {:system, :memory_percent, :gt, 85, :warning},
      {:disk, "/", :gt, 80, :warning},
      {:disk, "/", :gt, 95, :critical},
      {:docker, :container_stopped, :any, nil, :critical}
    ]
  end
end
