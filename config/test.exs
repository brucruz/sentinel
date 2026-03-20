import Config

config :logger, level: :warning

config :sentinel,
  telegram_bot_token: "test-token",
  telegram_chat_id: "test-chat-id",
  proc_base_path: "test/fixtures/proc",
  poll_intervals: %{system: :infinity, disk: :infinity, docker: :infinity, evaluator: :infinity},
  start_on_boot: false
