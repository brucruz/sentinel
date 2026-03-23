defmodule Sentinel.Docker.Client do
  @moduledoc """
  Low-level Docker Engine API client over unix socket.

  Uses Req to call the Docker API via /var/run/docker.sock.
  Only two endpoints needed: list containers and get container stats.
  """

  require Logger

  @docker_api_version "v1.45"

  @doc """
  Lists all containers (running and stopped).

  Returns a list of container maps from the Docker API.
  """
  def list_containers do
    get("/containers/json?all=true", receive_timeout: 5_000)
  end

  @doc """
  Gets resource usage stats for a single container (one-shot, no streaming).

  Returns CPU, memory, and network stats.
  """
  def container_stats(container_id) do
    get("/containers/#{container_id}/stats?stream=false", receive_timeout: 10_000)
  end

  defp get(path, opts) do
    socket = Sentinel.Config.docker_socket()
    url = "http://localhost/#{@docker_api_version}#{path}"

    case Req.get(url, [{:unix_socket, socket} | opts]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Docker API error: #{status} #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.warning("Docker API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
