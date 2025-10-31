import Config

version = System.version()

cond do
  Version.match?(version, "~> 1.19") ->
    config :logger, :default_handler, false

  Version.match?(version, "~> 1.15") ->
    # Allow tests to run by removing the default_backend
    config :logger, :backends, []

  true ->
    :ok
end
