defmodule Sentinel.Telegram.Middleware.AuthorizeChat do
  @moduledoc """
  ExGram middleware that rejects commands from unauthorized chat IDs.

  Only allows messages from the chat ID configured in `Sentinel.Config.telegram_chat_id/0`.
  """

  use ExGram.Middleware

  require Logger

  @impl true
  def call(%ExGram.Cnt{update: update} = cnt, _opts) do
    allowed_chat_id = Sentinel.Config.telegram_chat_id()

    case ExGram.Dsl.extract_id(update) do
      ^allowed_chat_id ->
        cnt

      chat_id when is_binary(chat_id) ->
        Logger.warning("Unauthorized Telegram chat: #{chat_id}")
        halt(cnt)

      chat_id when is_integer(chat_id) ->
        chat_id_str = Integer.to_string(chat_id)

        if chat_id_str == allowed_chat_id do
          cnt
        else
          Logger.warning("Unauthorized Telegram chat: #{chat_id}")
          halt(cnt)
        end

      _ ->
        Logger.warning("Could not extract chat ID from update")
        halt(cnt)
    end
  end
end
