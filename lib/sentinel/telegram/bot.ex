defmodule Sentinel.Telegram.Bot do
  @moduledoc """
  Telegram bot that handles on-demand commands like /status, /disk, /help.

  Uses ExGram for long-polling command routing.
  """

  use ExGram.Bot, name: :sentinel_bot

  alias Sentinel.Telegram.Formatter

  command("start", description: "Welcome message")
  command("status", description: "Full system overview")
  command("disk", description: "Disk usage per mount point")
  command("containers", description: "List all containers")
  command("container", description: "Detailed stats for one container")
  command("peak", description: "Peak CPU/MEM/SWAP over a window (e.g. 24h)")
  command("since", description: "Peak CPU/MEM/SWAP since ISO 8601 timestamp")
  command("help", description: "List available commands")

  middleware(ExGram.Middleware.IgnoreUsername)
  middleware(Sentinel.Telegram.Middleware.AuthorizeChat)

  def bot_name, do: :sentinel_bot

  @impl ExGram.Handler
  def handle({:command, :start, _msg}, cnt) do
    answer(cnt, Formatter.welcome_message(), parse_mode: "HTML")
  end

  def handle({:command, :status, _msg}, cnt) do
    text =
      Sentinel.MetricStore.snapshot()
      |> Formatter.status_message()

    answer(cnt, text, parse_mode: "HTML")
  end

  def handle({:command, :disk, _msg}, cnt) do
    text =
      Sentinel.MetricStore.snapshot(:disk)
      |> Formatter.disk_message()

    answer(cnt, text, parse_mode: "HTML")
  end

  def handle({:command, :containers, _msg}, cnt) do
    text =
      Sentinel.MetricStore.snapshot(:docker)
      |> Formatter.containers_message()

    answer(cnt, text, parse_mode: "HTML")
  end

  def handle({:command, :container, %{text: text}}, cnt) do
    name =
      text
      |> String.trim()
      |> String.replace(~r"^/container(@\w+)?\s*", "")
      |> String.trim()

    if name == "" do
      answer(cnt, "Usage: /container &lt;name&gt;\n\nExample: /container myapp-web")
    else
      text =
        Sentinel.MetricStore.snapshot(:docker)
        |> Formatter.container_detail_message(name)

      answer(cnt, text, parse_mode: "HTML")
    end
  end

  def handle({:command, :peak, %{text: text}}, cnt) do
    arg = command_arg(text, "peak")

    case parse_duration(arg) do
      {:ok, seconds, label} ->
        result = Sentinel.History.peak_over(seconds)
        answer(cnt, Formatter.peak_message(label, result), parse_mode: "HTML")

      :error ->
        answer(
          cnt,
          "Usage: /peak &lt;duration&gt;\n\nExamples: /peak 24h, /peak 30m, /peak 1d"
        )
    end
  end

  def handle({:command, :since, %{text: text}}, cnt) do
    arg = command_arg(text, "since")

    case parse_since(arg) do
      {:ok, since_ts, label} ->
        result = Sentinel.History.peak_since(since_ts)
        answer(cnt, Formatter.peak_message("since #{label}", result), parse_mode: "HTML")

      :error ->
        answer(
          cnt,
          "Usage: /since &lt;timestamp&gt;\n\nExample: /since 2026-05-12T05:00:00Z"
        )
    end
  end

  def handle({:command, :help, _msg}, cnt) do
    answer(cnt, Formatter.help_message(), parse_mode: "HTML")
  end

  def handle({:command, _unknown, _msg}, cnt) do
    answer(cnt, "Unknown command. Send /help for available commands.")
  end

  def handle(_msg, _cnt), do: :ok

  @doc false
  def command_arg(text, name) do
    text
    |> String.trim()
    |> String.replace(~r"^/#{name}(@\w+)?\s*", "")
    |> String.trim()
  end

  @doc false
  def parse_duration(""), do: {:ok, 24 * 60 * 60, "24h"}

  def parse_duration(str) do
    case Regex.run(~r/^(\d+)\s*(s|m|h|d)$/i, String.downcase(str)) do
      [_, num, unit] ->
        n = String.to_integer(num)

        seconds =
          case unit do
            "s" -> n
            "m" -> n * 60
            "h" -> n * 3600
            "d" -> n * 86_400
          end

        {:ok, seconds, "#{n}#{unit}"}

      _ ->
        :error
    end
  end

  @doc false
  def parse_since(""), do: :error

  def parse_since(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> {:ok, DateTime.to_unix(dt), DateTime.to_iso8601(dt)}
      _ -> :error
    end
  end
end
