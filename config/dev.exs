import Config

config :sentinel,
  telegram_bot_token: System.get_env("SENTINEL_TELEGRAM_TOKEN", "dev-token"),
  telegram_chat_id: System.get_env("SENTINEL_CHAT_ID", "dev-chat-id")
