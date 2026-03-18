import Config

if config_env() == :prod do
  config :sentinel,
    telegram_bot_token: System.fetch_env!("SENTINEL_TELEGRAM_TOKEN"),
    telegram_chat_id: System.fetch_env!("SENTINEL_CHAT_ID"),
    docker_socket: System.get_env("SENTINEL_DOCKER_SOCKET", "/var/run/docker.sock"),
    cooldown_minutes: String.to_integer(System.get_env("SENTINEL_COOLDOWN_MINUTES", "15"))
end
