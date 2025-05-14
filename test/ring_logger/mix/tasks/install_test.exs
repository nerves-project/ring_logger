defmodule RingLogger.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "installer adds ring_logger to existing target.exs" do
    test_project(
      files: %{
        "config/config.exs" => """
        import Config

        config :logger, level: :info
        config :other_thing, foo: :bar
        """
      }
    )
    |> Igniter.Project.Config.configure("config.exs", :logger, [:backends], [RingLogger])
    |> Igniter.compose_task("ring_logger.install", [])
    |> assert_has_patch("config/config.exs", ~S"""
     1 1   |import Config
     2 2   |
     3   - |config :logger, level: :info
       3 + |config :logger, level: :info, backends: [RingLogger]
     4 4   |config :other_thing, foo: :bar
       5 + |import_config "#{config_env()}.exs"
    """)
  end

  test "installer adds ring_logger to logger backends for target.exs" do
    test_project()
    |> Igniter.compose_task("ring_logger.install", [])
    |> assert_creates("config/config.exs", ~S"""
    import Config
    config :logger, backends: [RingLogger]
    import_config "#{config_env()}.exs"
    """)
  end
end
