# Local bot test script — starts only the Telegram bot with fake metrics.
# Skips /proc-dependent collectors (won't work on macOS).
#
# Usage: mix run --no-start scripts/local_bot.exs

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)
Application.ensure_all_started(:ex_gram)
Application.ensure_all_started(:req)

# Load .env
env = Dotenvy.source!([".env", System.get_env()])

Application.put_env(:sentinel, :telegram_bot_token, env["SENTINEL_TELEGRAM_TOKEN"])
Application.put_env(:sentinel, :telegram_chat_id, env["SENTINEL_CHAT_ID"])

# Start infrastructure
{:ok, _} = Finch.start_link(name: Sentinel.Finch)
{:ok, _} = Sentinel.MetricStore.start_link([])
{:ok, _} = ExGram.start_link([])

token = Sentinel.Config.telegram_bot_token()
chat_id = Sentinel.Config.telegram_chat_id()

IO.puts("Token: #{String.slice(token, 0, 10)}...")
IO.puts("Chat ID: #{chat_id}")

# Seed fake metrics
Sentinel.MetricStore.put(:system, :cpu_percent, 12.5)
Sentinel.MetricStore.put(:system, :memory, %{percent: 45.2, used_kb: 2_097_152, total_kb: 4_194_304})
Sentinel.MetricStore.put(:system, :loadavg, %{load1: 0.5, load5: 0.4, load15: 0.3})
Sentinel.MetricStore.put(:disk, "/", %{mount: "/", percent: 62, used_kb: 52_428_800, total_kb: 104_857_600})

# Start the bot
{:ok, _} = Sentinel.Telegram.Bot.start_link(method: :polling, token: token)

IO.puts("\nBot is running! Send /status, /disk, or /help in Telegram.")
IO.puts("Press Ctrl+C to stop.\n")

Process.sleep(:infinity)
