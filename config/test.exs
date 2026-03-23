import Config

config :logger, level: :warning

config :sentinel,
  telegram_bot_token: "test-token",
  telegram_chat_id: "123456",
  proc_base_path: "test/fixtures/proc",
  poll_intervals: %{system: :infinity, disk: :infinity, docker: :infinity, evaluator: :infinity},
  docker_client: Sentinel.Docker.ClientMock,
  system_backend: Sentinel.Collectors.System.Linux,
  thresholds: [],
  start_on_boot: false

config :ex_gram,
  token: "test-token",
  adapter: ExGram.Adapter.Test,
  updates: ExGram.Updates.Test
