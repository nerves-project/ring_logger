# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, backends: [Logger.RemoteConsole]

config :logger, Logger.RemoteConsole, buffer_size: 3
