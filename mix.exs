defmodule Logger.RemoteConsole.MixProject do
  use Mix.Project

  def project do
    [
      app: :logger_remote_console,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

end
