defmodule RingLogger.Client.Test do
  use ExUnit.Case, async: false
  alias RingLogger.Client

  setup do
    {:ok, client} = Client.start_link()
    # Elixir 1.4 changed the default pattern (removed $levelpad) so hardcode a default
    # pattern here
    Client.configure(client, format: "\n$time $metadata[$level] $message\n")
    {:ok, %{client: client}}
  end

  setup(context) do
    RingLogger.ApplicationEnvHelpers.with_application_env(context, &on_exit/1)
    :ok
  end

  describe "configure a client at runtime" do
    test "configure level", %{client: client} do
      Client.configure(client, level: :error)
      assert :error == :sys.get_state(client).level
    end

    test "configure colors", %{client: client} do
      colors = %{
        debug: :red,
        info: :normal,
        warn: :cyan,
        error: :yellow,
        enabled: IO.ANSI.enabled?()
      }

      Client.configure(client, colors: colors)

      assert colors == :sys.get_state(client).colors
    end

    test "configure metadata", %{client: client} do
      Client.configure(client, metadata: %{foo: :bar})
      assert [foo: :bar] == :sys.get_state(client).metadata
    end

    test "configure io", %{client: client} do
      Client.configure(client, io: :baz)
      assert :baz == :sys.get_state(client).io
    end

    test "configure format", %{client: client} do
      Client.configure(client, format: "Hello")
      assert ["Hello"] == :sys.get_state(client).format
    end

    test "cannot configure index", %{client: client} do
      Client.configure(client, index: :foo)
      refute :foo == :sys.get_state(client).index
    end

    test "configures with module_levels key", %{client: client} do
      module_levels = %{RingLogger => :info}

      Client.configure(client, module_levels: module_levels)

      assert :sys.get_state(client).module_levels == module_levels
    end

    test "configures module_levels from application_levels", %{client: client} do
      Client.configure(client, application_levels: %{ring_logger: :debug})

      module_levels = :sys.get_state(client).module_levels

      assert module_levels[RingLogger] == :debug
      assert module_levels[RingLogger.Client] == :debug
    end

    test "configuring module_level overwrites application_levels", %{client: client} do
      Client.configure(client,
        application_levels: %{ring_logger: :debug},
        module_levels: %{RingLogger => :info}
      )

      module_levels = :sys.get_state(client).module_levels

      assert module_levels[RingLogger] == :info
      assert module_levels[RingLogger.Client] == :debug
    end
  end

  test "can retrieve configuration", %{client: client} do
    config = [
      colors: %{debug: :cyan, enabled: true, error: :red, info: :normal, warn: :yellow},
      format: ["\n", :time, " ", :metadata, "[", :level, "] ", :message, "\n"],
      io: :stdio,
      level: :debug,
      metadata: [],
      module_levels: %{}
    ]

    assert Client.config(client) == config
  end

  @tag application_envs: [ring_logger: [colors: %{debug: :green, error: :blue}]]
  test "warns on deprecated config" do
    io_warning =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Client.start_link()
      end)

    assert io_warning =~ ~r/:ring_logger.*is deprecated/
  end

  @tag application_envs: [
         ring_logger: [colors: %{debug: :green, error: :blue}],
         logger: [{RingLogger, [colors: %{debug: :cyan}]}]
       ]
  test "non-deprecated config override deprecated config" do
    # Note: `error: :blue` in configuration will be overwritten because maps are not deep merged
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      {:ok, client} = Client.start_link()

      assert %{debug: :cyan} = :sys.get_state(client).colors
      assert :sys.get_state(client).level == :debug
    end)
  end
end
