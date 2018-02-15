# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, backends: [:console, RingLogger]

config :logger, RingLogger, max_size: 20
