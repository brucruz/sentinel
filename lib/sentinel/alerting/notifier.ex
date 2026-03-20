defmodule Sentinel.Alerting.Notifier do
  @moduledoc """
  Sends alert messages to Telegram via the Bot API.

  Stateless module — no GenServer. Uses Finch to POST to the Telegram API.
  """

  require Logger

  @telegram_api "https://api.telegram.org"

  def send_message(text, opts \\ []) do
    token = Keyword.get(opts, :token, Sentinel.Config.telegram_bot_token())
    chat_id = Keyword.get(opts, :chat_id, Sentinel.Config.telegram_chat_id())
    parse_mode = Keyword.get(opts, :parse_mode, "HTML")

    url = "#{base_url(opts)}/bot#{token}/sendMessage"

    body =
      Jason.encode!(%{
        chat_id: chat_id,
        text: text,
        parse_mode: parse_mode
      })

    request = Finch.build(:post, url, [{"content-type", "application/json"}], body)

    case Finch.request(request, Sentinel.Finch) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        {:ok, Jason.decode!(resp_body)}

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:error, {status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def check_connectivity(opts \\ []) do
    token = Keyword.get(opts, :token, Sentinel.Config.telegram_bot_token())
    url = "#{base_url(opts)}/bot#{token}/getMe"

    request = Finch.build(:get, url)

    case Finch.request(request, Sentinel.Finch) do
      {:ok, %Finch.Response{status: 200}} -> :ok
      {:ok, %Finch.Response{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_url(opts), do: Keyword.get(opts, :base_url, @telegram_api)
end
