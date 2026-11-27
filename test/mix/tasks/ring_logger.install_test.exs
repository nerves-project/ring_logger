# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.RingLogger.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @target_exs """
  import Config

  config :shoehorn, init: [:nerves_runtime, :nerves_pack]
  """

  defp nerves_project(files \\ %{}) do
    test_project(files: Map.merge(%{"config/target.exs" => @target_exs}, files))
  end

  defp install(igniter, argv \\ []) do
    Igniter.compose_task(igniter, "ring_logger.install", argv)
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  describe "Nerves project" do
    test "wires up RingLogger like mix nerves.new" do
      igniter = nerves_project() |> install()

      igniter
      |> assert_creates("config/runtime.exs", """
      import Config

      Application.ensure_all_started(:logger_backends)
      LoggerBackends.add(RingLogger)
      """)
      |> assert_has_patch("config/target.exs", """
      + |config :logger, default_handler: false
      """)
      |> assert_has_patch("mix.exs", """
      + |      {:logger_backends, "~> 1.0"}
      """)
      |> assert_unchanged("config/config.exs")

      assert igniter.notices == []
    end

    test "is idempotent" do
      nerves_project()
      |> install()
      |> apply_igniter!()
      |> install()
      |> assert_unchanged()
    end

    test "adds the backend to an existing runtime.exs" do
      nerves_project(%{
        "config/runtime.exs" => """
        import Config

        # Keep this
        if config_env() == :prod do
          config :my_app, key: System.fetch_env!("KEY")
        end
        """
      })
      |> install()
      |> assert_content_equals("config/runtime.exs", """
      import Config
      Application.ensure_all_started(:logger_backends)
      LoggerBackends.add(RingLogger)

      # Keep this
      if config_env() == :prod do
        config :my_app, key: System.fetch_env!("KEY")
      end
      """)
    end

    test "adds the backend to a runtime.exs that only has import Config" do
      nerves_project(%{"config/runtime.exs" => "import Config\n"})
      |> install()
      |> assert_content_equals("config/runtime.exs", """
      import Config
      Application.ensure_all_started(:logger_backends)
      LoggerBackends.add(RingLogger)
      """)
    end

    test "keeps other backends in runtime.exs" do
      nerves_project(%{
        "config/runtime.exs" => """
        import Config

        Application.ensure_all_started(:logger_backends)
        LoggerBackends.add(MyApp.OtherBackend)
        """
      })
      |> install()
      |> assert_content_equals("config/runtime.exs", """
      import Config

      Application.ensure_all_started(:logger_backends)
      LoggerBackends.add(RingLogger)
      LoggerBackends.add(MyApp.OtherBackend)
      """)
    end

    test "adds the backend to a runtime.exs without import Config" do
      nerves_project(%{"config/runtime.exs" => "IO.puts(\"hello\")\n"})
      |> install()
      |> assert_content_equals("config/runtime.exs", """
      Application.ensure_all_started(:logger_backends)
      LoggerBackends.add(RingLogger)
      IO.puts("hello")
      """)
    end

    test "leaves a runtime.exs that already adds RingLogger alone" do
      nerves_project(%{
        "config/runtime.exs" => """
        import Config

        if config_env() != :test do
          {:ok, _} = Application.ensure_all_started(:logger_backends)
          {:ok, _} = LoggerBackends.add(RingLogger, max_size: 2048)
        end
        """
      })
      |> install()
      |> assert_unchanged("config/runtime.exs")
    end

    test "merges into existing logger config" do
      nerves_project(%{
        "config/target.exs" => """
        import Config

        config :logger, level: :info
        config :logger, RingLogger, max_size: 2048
        config :other_thing, foo: :bar
        """
      })
      |> install()
      |> assert_has_patch("config/target.exs", """
      - |config :logger, level: :info
      + |config :logger, level: :info, default_handler: false
      """)
    end

    test "fits the target.exs that mix nerves.install creates" do
      nerves_project(%{
        "config/target.exs" => """
        import Config

        config :nerves, application_sort: [init: [:nerves_runtime]]

        # import_config "\#{Mix.target()}.exs"
        """
      })
      |> install()
      |> assert_content_equals("config/target.exs", """
      import Config

      config :logger, default_handler: false
      config :nerves, application_sort: [init: [:nerves_runtime]]

      # import_config "\#{Mix.target()}.exs"
      """)
    end

    test "keeps the user's default_handler setting" do
      nerves_project(%{
        "config/target.exs" => """
        import Config

        config :logger, :default_handler, level: :warning
        """
      })
      |> install()
      |> assert_unchanged("config/target.exs")
      |> assert_creates("config/runtime.exs")
    end

    test "keeps the user's logger_backends dependency" do
      igniter =
        nerves_project(%{
          "mix.exs" => """
          defmodule Test.MixProject do
            use Mix.Project

            def project do
              [app: :test, version: "0.1.0", deps: deps()]
            end

            defp deps do
              [
                {:logger_backends, "~> 1.0.1", optional: true}
              ]
            end
          end
          """
        })

      igniter = install(igniter)

      assert_unchanged(igniter, "mix.exs")
      assert igniter.tasks == []
    end

    test "only turns the console logger off for the device" do
      igniter = nerves_project() |> install()

      assert content(igniter, "config/target.exs") =~ "default_handler: false"
      assert_unchanged(igniter, "config/config.exs")
      refute_creates(igniter, "config/host.exs")
    end
  end

  describe "plain project" do
    test "adds the backend, but leaves the console logger on" do
      igniter = test_project() |> install()

      igniter
      |> assert_creates("config/runtime.exs", """
      import Config

      Application.ensure_all_started(:logger_backends)
      LoggerBackends.add(RingLogger)
      """)
      |> assert_has_patch("mix.exs", """
      + |      {:logger_backends, "~> 1.0"}
      """)
      |> refute_creates("config/target.exs")
      |> refute_creates("config/config.exs")
      |> assert_has_notice(&(&1 =~ "config/target.exs was not found"))
    end

    test "leaves config.exs alone" do
      igniter =
        test_project(
          files: %{
            "config/config.exs" => """
            import Config

            config :logger, level: :info
            """
          }
        )
        |> install()

      assert_unchanged(igniter, "config/config.exs")
      refute content(igniter, "config/config.exs") =~ "default_handler"
    end

    test "is idempotent" do
      test_project()
      |> install()
      |> apply_igniter!()
      |> install()
      |> assert_unchanged()
    end
  end

  describe "project using the deprecated :backends key" do
    test "is left alone when RingLogger is in the keyword form" do
      igniter =
        nerves_project(%{
          "config/config.exs" => """
          import Config

          config :logger, level: :info, backends: [:console, RingLogger]
          """
        })
        |> install()

      igniter
      |> assert_unchanged()
      |> assert_has_notice(&(&1 =~ "already listed under `config :logger, backends: [...]`"))

      assert hd(igniter.notices) =~ "config/config.exs"
    end

    test "is left alone when RingLogger is in the 3-arity form" do
      nerves_project(%{
        "config/target.exs" => """
        import Config

        config :logger, :backends, [RingLogger]
        """
      })
      |> install()
      |> assert_unchanged()
      |> assert_has_notice(&(&1 =~ "config/target.exs"))
    end

    test "other backends don't count" do
      nerves_project(%{
        "config/config.exs" => """
        import Config

        config :logger, backends: [:console]
        config :logger, RingLogger, max_size: 1024
        """
      })
      |> install()
      |> assert_unchanged("config/config.exs")
      |> assert_creates("config/runtime.exs")
    end
  end
end
