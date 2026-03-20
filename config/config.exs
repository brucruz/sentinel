import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module]

config :ex_gram, adapter: ExGram.Adapter.Req

import_config "#{config_env()}.exs"
