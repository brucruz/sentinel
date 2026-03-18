import Config
import Dotenvy

# In dev/test, load from .env file. In prod, systemd provides env vars via EnvironmentFile.
# System.get_env() is always included so real env vars take precedence.
source!([
  if(config_env() in [:dev, :test], do: ".env"),
  System.get_env()
])

config :sentinel,
  telegram_bot_token: env!("SENTINEL_TELEGRAM_TOKEN", :string!),
  telegram_chat_id: env!("SENTINEL_CHAT_ID", :string!),
  docker_socket: env!("SENTINEL_DOCKER_SOCKET", :string, "/var/run/docker.sock"),
  cooldown_minutes: env!("SENTINEL_COOLDOWN_MINUTES", :integer, 15)
