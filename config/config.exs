import Config

if Version.match?(System.version(), "~> 1.15") do
  # Allow tests to run by removing the default_backend
  config :logger, :backends, []
end
