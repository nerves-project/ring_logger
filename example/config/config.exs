import Config

config :logger, backends: [:console, RingLogger]

config :logger, RingLogger, max_size: 20
