defmodule RingLoggerTest do
  use ExUnit.Case, async: false
  doctest RingLogger

  import ExUnit.CaptureIO

  alias RingLogger.Persistence
  alias RingLogger.TestCustomFormatter

  require Logger

  # Elixir 1.4 changed the default pattern (removed $levelpad) so hardcode a default
  # pattern here
  @default_pattern "\n$time $metadata[$level] $message\n"

  setup do
    {:ok, pid} = RingLogger.TestIO.start(self())

    # This next line is for Elixir 1.14 and earlier. Elixir 1.15 relies on the config.exs
    # to remove the console backend (err, default handler).
    Logger.remove_backend(:console)

    # Flush any latent messages in the Logger to avoid them polluting
    # our tests
    Logger.flush()

    Logger.add_backend(RingLogger)
    Logger.configure_backend(RingLogger, max_size: 10, format: @default_pattern, buffers: [])

    on_exit(fn ->
      RingLogger.TestIO.stop(pid)
      Logger.remove_backend(RingLogger)
    end)

    {:ok, [io: pid]}
  end

  # Ensure that a log message makes it way through the logger processes.
  #
  # The RingLogger needs to be attached for this to work. This makes
  # logging synchronous so that we can test tail, next, grep, etc. that
  # rely on the messages being received by RingLogger.
  defp handshake_log(io, level, message, metadata \\ []) do
    Logger.log(level, message, metadata)
    assert_receive {:io, msg}
    assert String.contains?(msg, to_string(level))

    flattened_message = IO.chardata_to_string(message)
    assert String.contains?(msg, flattened_message)
    io
  end

  test "can attach", %{io: io} do
    :ok = RingLogger.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "attaching twice doesn't duplicate messages", %{io: io} do
    :ok = RingLogger.attach(io: io)
    :ok = RingLogger.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    refute_receive {:io, _}
  end

  test "attach, detach, attach works", %{io: io} do
    :ok = RingLogger.attach(io: io)
    :ok = RingLogger.detach()
    :ok = RingLogger.attach(io: io)
  end

  test "output is not duplicated on group leader", %{io: io} do
    :ok = RingLogger.attach(io: io)

    output =
      capture_log(fn ->
        Logger.debug("Hello")
      end)

    assert output == ""
  end

  test "can receive multiple messages", %{io: io} do
    :ok = RingLogger.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "[debug] World"
  end

  test "can detach", %{io: io} do
    :ok = RingLogger.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    RingLogger.detach()
    Logger.debug("World")
    refute_receive {:io, _}
  end

  test "can filter based on log level", %{io: io} do
    :ok = RingLogger.attach(io: io, level: :error)
    Logger.debug("Hello")
    refute_receive {:io, _message}
    Logger.error("World")
    assert_receive {:io, message}
    assert message =~ "[error] World"
  end

  test "can grep log", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can grep iodata in log", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, ["Hello", ",", ~c" world"])
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert message =~ "[debug] Hello, world"
  end

  test "can grep using a string", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep("H..lo", io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can colorize grep log", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: true])
    assert_receive {:io, message}
    assert message =~ "[debug] #{IO.ANSI.inverse()}Hello#{IO.ANSI.inverse_off()}"
  end

  test "can grep before and after lines", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "b3")
    |> handshake_log(:debug, "b2")
    |> handshake_log(:debug, "b1")
    |> handshake_log(:debug, "howdy")
    |> handshake_log(:debug, "a1")
    |> handshake_log(:debug, "a2")
    |> handshake_log(:debug, "a3")

    RingLogger.grep(~r/howdy/, before: 2, after: 2, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    refute message =~ "[debug] b3"
    assert message =~ "[debug] b2"
    assert message =~ "[debug] b1"
    assert message =~ "[debug] howdy"
    assert message =~ "[debug] a1"
    assert message =~ "[debug] a2"
    refute message =~ "[debug] a3"
  end

  test "can grep based on metadata with exact match", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "b3")
    |> handshake_log(:debug, "b2")
    |> handshake_log(:debug, "b1")
    |> handshake_log(:debug, "howdy", session_id: "user_1")
    |> handshake_log(:debug, "a1")
    |> handshake_log(:debug, "a2")
    |> handshake_log(:debug, "a3")

    :ok = RingLogger.grep_metadata(:session_id, "user_1")
    assert_receive {:io, message}
    refute message =~ "[debug] b1"
    refute message =~ "[debug] b2"
    refute message =~ "[debug] b3"
    assert message =~ "howdy"
    refute message =~ "[debug] a1"
    refute message =~ "[debug] a2"
    refute message =~ "[debug] a3"
  end

  test "can grep based on metadata with regexp", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "b3")
    |> handshake_log(:debug, "b2")
    |> handshake_log(:debug, "b1")
    |> handshake_log(:debug, "howdy", session_id: "user_1")
    |> handshake_log(:debug, "hello", session_id: "user_2")
    |> handshake_log(:debug, "john", session_id: "irrelevant_1")
    |> handshake_log(:debug, "doe", session_id: "irrelevant_2")
    |> handshake_log(:debug, "a1")
    |> handshake_log(:debug, "a2")
    |> handshake_log(:debug, "a3")

    :ok = RingLogger.grep_metadata(:session_id, ~r/user/)
    assert_receive {:io, message}
    refute message =~ "[debug] b1"
    refute message =~ "[debug] b2"
    refute message =~ "[debug] b3"
    assert message =~ "howdy" or message =~ "hello"
    refute message =~ "john"
    refute message =~ "joe"
    refute message =~ "[debug] a1"
    refute message =~ "[debug] a2"
    refute message =~ "[debug] a3"
  end

  test "invalid regex returns error", %{io: io} do
    assert {:error, _} = RingLogger.grep(5, io: io)
  end

  test "can next the log", %{io: io} do
    :ok = RingLogger.attach(io: io)
    handshake_log(io, :debug, "Hello")

    :ok = RingLogger.next(io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    :ok = RingLogger.next()
    assert_receive {:io, messages}

    assert messages =~ "[debug] Foo"
    assert messages =~ "[debug] Bar"
  end

  test "can reset to the beginning", %{io: io} do
    :ok = RingLogger.attach(io: io)
    handshake_log(io, :debug, "Hello")

    :ok = RingLogger.next(io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    :ok = RingLogger.reset()
    :ok = RingLogger.next()
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can tail the log", %{io: io} do
    :ok = RingLogger.attach(io: io)
    :ok = RingLogger.tail(io: io)
    assert_receive {:io, ""}

    handshake_log(io, :debug, "Hello")
    :ok = RingLogger.tail()
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    :ok = RingLogger.tail()

    assert_receive {:io, messages}

    assert messages =~ "[debug] Hello"
    assert messages =~ "[debug] Foo"
    assert messages =~ "[debug] Bar"

    :ok = RingLogger.tail(1)
    assert_receive {:io, message}
    assert message =~ "[debug] Bar"
    refute message =~ "[debug] Hello"
    refute message =~ "[debug] Foo"
  end

  test "can get buffer", %{io: io} do
    :ok = RingLogger.attach(io: io)
    handshake_log(io, :debug, "Hello")

    buffer = RingLogger.get()
    assert [%{level: :debug, module: Logger, message: "Hello"}] = buffer
  end

  test "buffer does not exceed size", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 2)
    :ok = RingLogger.attach(io: io)

    handshake_log(io, :debug, "Foo")

    buffer = RingLogger.get()
    assert [%{level: :debug, module: Logger, message: "Foo"}] = buffer

    handshake_log(io, :debug, "Bar")

    buffer = RingLogger.get()

    assert [
             %{level: :debug, module: Logger, message: "Foo"},
             %{level: :debug, module: Logger, message: "Bar"}
           ] = buffer

    handshake_log(io, :debug, "Baz")

    buffer = RingLogger.get()

    assert [
             %{level: :debug, module: Logger, message: "Bar"},
             %{level: :debug, module: Logger, message: "Baz"}
           ] = buffer
  end

  test "buffer can be fetched by range", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 3)
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")
    |> handshake_log(:debug, "Baz")

    buffer = RingLogger.get(2)
    assert [%{level: :debug, module: Logger, message: "Baz"}] = buffer
    buffer = RingLogger.get(1)

    assert [
             %{level: :debug, module: Logger, message: "Bar"},
             %{level: :debug, module: Logger, message: "Baz"}
           ] = buffer
  end

  test "next supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:info, "Hello")
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    # Even though the intention for a custom pager is to "page" the output to the user,
    # just print out the number of characters as a check that the custom function is
    # actually run.
    :ok =
      RingLogger.next(
        pager: fn device, msg ->
          IO.write(device, "Got #{String.length(IO.chardata_to_string(msg))} characters")
        end
      )

    assert_receive {:io, messages}

    assert messages =~ "Got 138 characters"
  end

  test "tail supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:info, "Hello")
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    :ok =
      RingLogger.tail(2,
        pager: fn device, msg ->
          IO.write(device, "Got #{String.length(IO.chardata_to_string(msg))} characters")
        end
      )

    assert_receive {:io, messages}

    assert messages =~ "Got 70 characters"
  end

  test "grep supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:info, "Hello")
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    :ok =
      RingLogger.grep(~r/debug/,
        pager: fn device, msg ->
          IO.write(device, "Got #{String.length(IO.chardata_to_string(msg))} characters")
        end
      )

    assert_receive {:io, messages}

    assert messages =~ "Got 88 characters"
  end

  test "buffer start index is less then buffer_start_index", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 1)

    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    buffer = RingLogger.get(0)
    assert [%{level: :debug, module: Logger, message: "Bar"}] = buffer
  end

  test "receive nothing when fetching buffer out of range" do
    assert [] = RingLogger.get(100)
  end

  test "buffer can be paged", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 3)
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")
    |> handshake_log(:debug, "Baz")

    buffer = RingLogger.get(1, 1)
    assert [%{level: :debug, module: Logger, message: "Bar"}] = buffer

    buffer = RingLogger.get(1, 2)

    assert [
             %{level: :debug, module: Logger, message: "Bar"},
             %{level: :debug, module: Logger, message: "Baz"}
           ] = buffer

    buffer = RingLogger.get(1, 3)

    assert [
             %{level: :debug, module: Logger, message: "Bar"},
             %{level: :debug, module: Logger, message: "Baz"}
           ] = buffer
  end

  test "can format messages", %{io: io} do
    :ok = RingLogger.attach(io: io, format: "$metadata$message", metadata: [:index])

    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "index=0 Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "index=1 World"
  end

  test "can use custom formatter", %{io: io} do
    :ok = RingLogger.attach(io: io, format: {TestCustomFormatter, :format}, metadata: [:index])

    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "index=0 Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "index=1 World"
  end

  test "can filter levels by module", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :info})

    Logger.info("foo")
    assert_receive {:io, _message}
    Logger.debug("bar")
    refute_receive {:io, _message}
    Logger.warning("baz")
    assert_receive {:io, _message}
  end

  test "can filter all levels by module", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :none})

    Logger.info("foo")
    refute_receive {:io, _message}
    Logger.debug("bar")
    refute_receive {:io, _message}
    Logger.warning("baz")
    refute_receive {:io, _message}
    Logger.error("uhh")
    refute_receive {:io, _message}
  end

  test "can filter module level to print lower than logger level", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :debug}, level: :warning)

    Logger.debug("Hello world")
    assert_receive {:io, _message}
  end

  test "can filter module level with grep", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :info})
    handshake_log(io, :info, "Hello")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert String.contains?(message, "[info] Hello")
  end

  test "can save to a file", %{io: io} do
    :ok = RingLogger.attach(io: io)
    handshake_log(io, :debug, "Hello")

    filename = "ringlogger-test-save.log"
    File.rm(filename)
    :ok = RingLogger.save(filename)

    assert File.exists?(filename)

    contents = File.read!(filename)
    assert contents =~ "[debug] Hello"

    File.rm!(filename)
  end

  test "returns error when saving to a bad path", %{io: io} do
    :ok = RingLogger.attach(io: io)
    handshake_log(io, :debug, "Hello")

    # This better not exist...
    assert {:error, :enoent} == RingLogger.save("/a/b/c/d/e/f/g")
  end

  test "logging chardata", %{io: io} do
    :ok = RingLogger.attach(io: io)
    Logger.info(~c"Cześć!")
    assert_receive {:io, message}
    assert message =~ "[info] Cześć!"
  end

  test "logging corrupt data", %{io: io} do
    # This is non-Unicode and shouldn't crash RingLogger. There are slightly
    # different paths that are taken for iodata vs binary data, so make sure
    # they behave identically.
    message_string = <<227, 97, 195, 253, 123, 50, 91, 116, 114, 227, 110>>
    message = [message_string]

    :ok = RingLogger.attach(io: io)
    Logger.debug(message_string)
    assert_receive {:io, message_string_result}

    Logger.debug(message)
    assert_receive {:io, message_result}

    assert message_result == message_string_result
    assert message_result =~ "{2[tr"
  end

  test "logging totally wrong data doesn't crash", %{io: io} do
    :ok = RingLogger.attach(io: io)
    Logger.info([[{1, 2, 3}]])
    assert_receive {:io, message}
    assert message =~ "[info] cannot truncate chardata"
  end

  describe "fetching config" do
    test "can retrieve config for attached client", %{io: io} do
      :ok = RingLogger.attach(io: io)

      config = [
        colors: %{debug: :cyan, enabled: true, error: :red, info: :normal, warn: :yellow},
        format: ["\n", :time, " ", :metadata, "[", :level, "] ", :message, "\n"],
        io: io,
        level: :debug,
        metadata: [],
        module_levels: %{}
      ]

      got = RingLogger.config() |> Enum.sort()

      assert got == config
    end

    test "returns error when no attached client" do
      assert RingLogger.config() == {:error, :no_client}
    end
  end

  describe "multiple buffers" do
    test "setting multiple buffers", %{io: io} do
      Logger.configure_backend(RingLogger,
        buffers: %{
          errors: %{
            levels: [:warning, :errors],
            max_size: 10
          }
        }
      )

      :ok = RingLogger.attach(io: io)
    end

    test "different levels use different buffers", %{io: io} do
      Logger.configure_backend(RingLogger,
        buffers: %{
          debug: %{
            levels: [:debug],
            max_size: 10
          },
          error: %{
            levels: [:error],
            max_size: 10
          }
        }
      )

      :ok = RingLogger.attach(io: io)

      io
      |> handshake_log(:error, "one")
      |> handshake_log(:error, "two")
      |> handshake_log(:error, "three")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:debug, "bar")

      buffer = RingLogger.get(0, 0)

      # Should include the first 3 errors
      [%{level: :error}, %{level: :error}, %{level: :error} | _] = buffer
    end

    test "multiple buffers and indexing", %{io: io} do
      Logger.configure_backend(RingLogger,
        buffers: %{
          debug: %{
            levels: [:debug],
            max_size: 3
          },
          error: %{
            levels: [:error],
            max_size: 3
          }
        }
      )

      :ok = RingLogger.attach(io: io)

      io
      |> handshake_log(:error, "one")
      |> handshake_log(:error, "two")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:error, "three")
      |> handshake_log(:debug, "bar")

      buffer = RingLogger.get(2, 3)

      [%{level: :debug}, %{level: :error}, %{level: :debug}] = buffer
    end

    test "`get(starting_index, 0)` returns everything after the starting index", %{io: io} do
      Logger.configure_backend(RingLogger,
        buffers: %{
          debug: %{
            levels: [:debug],
            max_size: 3
          },
          error: %{
            levels: [:error],
            max_size: 3
          }
        }
      )

      :ok = RingLogger.attach(io: io)

      io
      |> handshake_log(:error, "one")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:error, "two")
      |> handshake_log(:error, "three")
      |> handshake_log(:debug, "bar")

      buffer = RingLogger.get(1, 0)

      [%{level: :debug}, %{level: :error}, %{level: :error}, %{level: :debug}] = buffer
    end

    test "tailing multiple buffers", %{io: io} do
      Logger.configure_backend(RingLogger,
        buffers: %{
          debug: %{
            levels: [:debug],
            max_size: 3
          },
          error: %{
            levels: [:error],
            max_size: 3
          }
        }
      )

      :ok = RingLogger.attach(io: io)

      io
      |> handshake_log(:error, "one")
      |> handshake_log(:debug, "bar")
      |> handshake_log(:error, "two")
      |> handshake_log(:error, "three")
      |> handshake_log(:debug, "baz")

      :ok = RingLogger.tail(3)

      assert_receive {:io, logs}

      logs = String.replace(logs, "\n", " ")

      assert logs =~ ~r/\[error\] two.+\[error\] three.+\[debug\] baz/
    end
  end

  describe "persistence" do
    test "loading the log", %{io: io} do
      Logger.remove_backend(RingLogger)

      logs = [
        %{
          level: :debug,
          module: Logger,
          message: "Foo",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
          metadata: []
        },
        %{
          level: :debug,
          module: Logger,
          message: "Bar",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
          metadata: []
        }
      ]

      :ok = Persistence.save("test/persistence.log", logs)

      # Start the backend with _just_ the persist_path and restore old
      # config to allow other tests to run without loading a log file
      old_env = Application.get_env(:logger, RingLogger)
      Application.put_env(:logger, RingLogger, persist_path: "test/persistence.log")
      Logger.add_backend(RingLogger)
      Application.put_env(:logger, RingLogger, old_env)

      Logger.add_backend(RingLogger)

      :ok = RingLogger.attach(io: io)

      buffer = RingLogger.get(0, 0)

      assert Enum.count(buffer) == 2

      File.rm!("test/persistence.log")
    end

    test "loading the log with multiple buffers", %{io: io} do
      Logger.remove_backend(RingLogger)

      logs = [
        %{
          level: :debug,
          module: Logger,
          message: "Foo",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
          metadata: []
        },
        %{
          level: :debug,
          module: Logger,
          message: "Bar",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 344}},
          metadata: []
        },
        %{
          level: :info,
          module: Logger,
          message: "Baz",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 345}},
          metadata: []
        }
      ]

      :ok = Persistence.save("test/persistence.log", logs)

      # Start the backend with _just_ the persist_path and restore old
      # config to allow other tests to run without loading a log file
      old_env = Application.get_env(:logger, RingLogger)

      new_env = [
        persist_path: "test/persistence.log",
        max_size: 3,
        buffers: %{debug: %{levels: [:debug], max_size: 2}}
      ]

      Application.put_env(:logger, RingLogger, new_env)
      Logger.add_backend(RingLogger)
      Application.put_env(:logger, RingLogger, old_env)

      Logger.add_backend(RingLogger)

      :ok = RingLogger.attach(io: io)

      buffer = RingLogger.get(0, 0)

      assert Enum.count(buffer) == 3

      File.rm!("test/persistence.log")
    end

    test "loading a corrupted file", %{io: io} do
      Logger.remove_backend(RingLogger)

      File.write!("test/persistence.log", "this is corrupt")

      # Start the backend with _just_ the persist_path and restore old
      # config to allow other tests to run without loading a log file
      old_env = Application.get_env(:logger, RingLogger)
      Application.put_env(:logger, RingLogger, persist_path: "test/persistence.log")
      Logger.add_backend(RingLogger)
      Application.put_env(:logger, RingLogger, old_env)

      :ok = RingLogger.attach(io: io)

      buffer = RingLogger.get(0, 0)

      assert Enum.count(buffer) == 1

      File.rm!("test/persistence.log")
    end

    test "loading the log resets indexes", %{io: io} do
      Logger.remove_backend(RingLogger)

      logs = [
        %{
          level: :debug,
          module: Logger,
          message: "Foo",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
          metadata: [index: 5000]
        },
        %{
          level: :debug,
          module: Logger,
          message: "Bar",
          timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
          metadata: [index: 6000]
        }
      ]

      :ok = Persistence.save("test/persistence.log", logs)

      # Start the backend with _just_ the persist_path and restore old
      # config to allow other tests to run without loading a log file
      old_env = Application.get_env(:logger, RingLogger)
      Application.put_env(:logger, RingLogger, persist_path: "test/persistence.log")
      Logger.add_backend(RingLogger)
      Application.put_env(:logger, RingLogger, old_env)

      Logger.add_backend(RingLogger)

      :ok = RingLogger.attach(io: io)

      [foo, bar] = RingLogger.get(0, 0)

      assert foo.message == "Foo"
      assert foo.metadata[:index] == 0

      assert bar.message == "Bar"
      assert bar.metadata[:index] == 1

      File.rm!("test/persistence.log")
    end

    test "persists on terminate", %{io: io} do
      Logger.remove_backend(RingLogger)

      _ = File.rm("test/persistence.log")

      # Start the backend with _just_ the persist_path and restore old
      # config to allow other tests to run without loading a log file
      old_env = Application.get_env(:logger, RingLogger)
      Application.put_env(:logger, RingLogger, persist_path: "test/persistence.log")
      Logger.add_backend(RingLogger)
      Application.put_env(:logger, RingLogger, old_env)

      Logger.add_backend(RingLogger)

      :ok = RingLogger.attach(io: io)

      Logger.info("Hello")

      # Logs should save since we're terminating the backend
      Logger.remove_backend(RingLogger)

      assert File.exists?("test/persistence.log")

      File.rm!("test/persistence.log")
    end
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
