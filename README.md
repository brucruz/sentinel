# Sentinel

Sentinel is a small Elixir/OTP application that monitors a single VPS and reports to Telegram. It polls CPU, memory, swap, disk and Docker container state, sends an alert when a threshold is crossed, and answers status queries from a Telegram bot. It was built to watch a server running Docker containers without running a separate monitoring stack: one release, one systemd unit, no database.

## Features

- System metrics: CPU, memory, swap and load average. On Linux these come from `/proc`; on macOS a Darwin backend uses `sysctl`, `vm_stat` and `top`, so the app can run on a development machine.
- Disk usage per mount point, read from `df -Pk`.
- Docker container state and per-container CPU and memory stats, read from the Docker Engine API over the Unix socket.
- Threshold alerts, checked every 30 seconds:

  | Check | Condition | Severity |
  |---|---|---|
  | CPU | above 90% | warning |
  | Memory | above 85% | warning |
  | Disk `/` | above 80% | warning |
  | Disk `/` | above 95% | critical |
  | Container | not running | critical |

- Stopped-container alerts are suppressed when a running container has the same name apart from a trailing hex hash (12 or more characters). This avoids alerting on the old container left behind when a new release of the same service starts, as happens with Kamal deploys.
- A per-alert cooldown (15 minutes by default) so a sustained condition does not repeat on every check.
- A rolling 24-hour history of CPU, memory, swap and load, sampled at the system collector's 10-second interval, used for peak queries.
- A Telegram bot, using long polling, that accepts these commands:

  | Command | Description |
  |---|---|
  | `/start` | Welcome message |
  | `/status` | Full system overview |
  | `/disk` | Disk usage per mount point |
  | `/containers` | List all containers |
  | `/container <name>` | Detailed stats for one container |
  | `/peak <duration>` | Peak CPU, memory and swap over a window such as `30m`, `24h` or `1d` (default `24h`) |
  | `/since <timestamp>` | Peak CPU, memory and swap since an ISO 8601 timestamp |
  | `/help` | List available commands |

- Chat authorization: a middleware drops every update that does not come from the chat ID in `SENTINEL_CHAT_ID`.
- A startup message is sent to the configured chat when the application boots and Telegram is reachable.

## Architecture

```
Sentinel.Supervisor (one_for_one)
├── Finch (HTTP pool)
├── Sentinel.MetricStore          ETS table: latest value per {collector, metric}
├── Sentinel.History              ETS ordered_set: 24h time series
├── Sentinel.Collectors.Supervisor (one_for_one)
│   ├── Collectors.System         /proc or Darwin backend, every 10s
│   ├── Collectors.Disk           every 60s
│   └── Collectors.Docker         every 15s
├── startup message task (temporary)
├── Sentinel.Alerting.Supervisor (one_for_one)
│   └── Alerting.Cooldown         ETS table: last-fired time per alert key
├── Sentinel.Evaluator            thresholds vs. MetricStore, every 30s
├── ExGram
└── Sentinel.Telegram.Bot         long polling, AuthorizeChat middleware
```

Design choices visible in the code:

- Collectors implement `Sentinel.Collectors.Behaviour` (`collect/0` and `interval/0`) and each runs as its own GenServer that reschedules itself with `Process.send_after/3`. The system collector selects a backend module at startup, which lets tests run against `/proc` fixtures.
- State is in memory only. The metric store, history and cooldowns are public ETS tables owned by GenServers, so readers (the evaluator and the bot) do not go through a process mailbox. State is lost on restart, and the collectors repopulate it within one polling interval.
- Everything is polling: collectors poll the host and Docker, the evaluator polls the metric store, and the bot polls Telegram. There are no inbound ports.
- Collectors, alerting and the bot are separate supervision subtrees with `one_for_one` strategies, so a failing collector does not restart the others.
- Thresholds are plain tuples in `Sentinel.Config`, matched by `Sentinel.Evaluator.check_threshold/2`, and can be overridden through application config.

## Configuration

Configuration is read from environment variables in `config/runtime.exs`. In dev and test, a `.env` file is loaded first; real environment variables take precedence. In production, systemd supplies them from `/etc/sentinel/env`.

| Variable | Required | Default | Description |
|---|---|---|---|
| `SENTINEL_TELEGRAM_TOKEN` | yes | | Telegram bot token |
| `SENTINEL_CHAT_ID` | yes | | The only chat allowed to use the bot; alerts are sent here |
| `SENTINEL_DOCKER_SOCKET` | no | `/var/run/docker.sock`, or `~/.docker/run/docker.sock` if that exists instead | Path to the Docker Engine socket |
| `SENTINEL_COOLDOWN_MINUTES` | no | `15` | Minimum time before the same alert fires again |

## Running locally

Requires Elixir 1.19 or newer.

```sh
cp .env.example .env    # fill in the token and chat ID
mix deps.get
mix run --no-halt
```

The scripts in `scripts/` exercise parts of the system without starting the full application:

- `mix run --no-start scripts/local_collectors.exs` runs the collectors against your machine. It works on macOS and Linux.
- `mix run --no-start scripts/local_docker.exs` calls the Docker API against your local Docker socket. Set `DOCKER_SOCKET` if it is not at `~/.docker/run/docker.sock`.
- `mix run --no-start scripts/local_bot.exs` starts only the Telegram bot with fake metrics, so you can try the commands. It needs the token and chat ID in `.env`.

## Tests

```sh
mix test
```

The suite has about 97 ExUnit tests. Telegram API calls are tested with Bypass, the Docker client is replaced by a mock (`test/support/docker_client_mock.ex`), and the Linux system backend reads fixtures from `test/fixtures/proc`. The test environment sets all polling intervals to `:infinity` and starts only the Finch pool at boot, so tests drive the collectors and the evaluator directly.

## Deployment

Sentinel is released with `mix release` (ERTS included) and runs as a systemd service.

- `deploy/setup-vps.sh` prepares the server once. It creates a `sentinel` system user in the `docker` group, creates `/opt/sentinel` and `/etc/sentinel`, and installs the env file.
- `.github/workflows/deploy.yml` runs on every push to `main`. It builds the release on Elixir 1.19 and OTP 28, stops the service, copies the release to `/opt/sentinel/` with `rsync`, installs `deploy/sentinel.service`, and starts the service. The workflow needs the secrets `VPS_HOST`, `VPS_USER` and `SSH_PRIVATE_KEY`.
- `deploy/sentinel.service` runs the release as the `sentinel` user, reads its environment from `/etc/sentinel/env`, and restarts on failure after 5 seconds.

Logs are available with `sudo journalctl -u sentinel -f`.
