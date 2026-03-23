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

  def handle({:command, :help, _msg}, cnt) do
    answer(cnt, Formatter.help_message(), parse_mode: "HTML")
  end

  def handle({:command, _unknown, _msg}, cnt) do
    answer(cnt, "Unknown command. Send /help for available commands.")
  end

  def handle(_msg, _cnt), do: :ok
end
