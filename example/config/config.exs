# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, backends: [Logger.CircularBuffer]

config :logger, Logger.CircularBuffer, buffer_size: 3
