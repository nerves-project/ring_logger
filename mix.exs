defmodule RingLogger.MixProject do
  use Mix.Project

  @version "0.10.5"
  @source_url "https://github.com/nerves-project/ring_logger"

  def project do
    [
      app: :ring_logger,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      preferred_cli_env: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:circular_buffer, "~> 0.4.0"},
      {:benchee, "~> 1.1", only: :dev},
      {:ex_doc, "~> 0.18", only: :docs, runtime: false},
      {:dialyxir, "~> 1.2", only: :dev, runtime: false},
      {:credo, "~> 1.5", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A ring buffer backend for Elixir Logger with IO streaming"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp dialyzer() do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs]
    ]
  end
end
