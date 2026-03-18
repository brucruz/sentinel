import Config

config :logger, level: :warning

config :sentinel,
  telegram_bot_token: "test-token",
  telegram_chat_id: "test-chat-id"
