defmodule RingLoggerTest do
  use ExUnit.Case, async: false
  doctest RingLogger

  import ExUnit.CaptureIO

  require Logger

  # Elixir 1.4 changed the default pattern (removed $levelpad) so hardcode a default
  # pattern here
  @default_pattern "\n$time $metadata[$level] $message\n"

  setup do
    {:ok, pid} = RingLogger.TestIO.start(self())

    # Ensure all log levels pass through the global logger to our handler
    old_level = :logger.get_primary_config().level
    :logger.set_primary_config(:level, :all)

    # Flush any latent messages in the Logger to avoid them polluting
    # our tests
    Logger.flush()

    :ok = RingLogger.add(max_size: 10)

    on_exit(fn ->
      RingLogger.TestIO.stop(pid)
      _ = RingLogger.remove()
      :logger.set_primary_config(:level, old_level)
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
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "attaching twice doesn't duplicate messages", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    refute_receive {:io, _}
  end

  test "attach, detach, attach works", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    :ok = RingLogger.detach()
    :ok = RingLogger.attach(io: io, format: @default_pattern)
  end

  test "output is not duplicated on group leader", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    output =
      capture_log(fn ->
        Logger.debug("Hello")
      end)

    assert output == ""
  end

  test "can receive multiple messages", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "[debug] World"
  end

  test "can detach", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    RingLogger.detach()
    Logger.debug("World")
    refute_receive {:io, _}
  end

  test "can filter based on log level", %{io: io} do
    :ok = RingLogger.attach(io: io, level: :error, format: @default_pattern)
    Logger.debug("Hello")
    refute_receive {:io, _message}
    Logger.error("World")
    assert_receive {:io, message}
    assert message =~ "[error] World"
  end

  test "can grep log", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can grep iodata in log", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, ["Hello", ",", ~c" world"])
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert message =~ "[debug] Hello, world"
  end

  test "can grep using a string", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep("H..lo", io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can colorize grep log", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: true])
    assert_receive {:io, message}
    assert message =~ "[debug] #{IO.ANSI.inverse()}Hello#{IO.ANSI.inverse_off()}"
  end

  test "can grep before and after lines", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

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
    :ok = RingLogger.attach(io: io, format: @default_pattern)

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
    :ok = RingLogger.attach(io: io, format: @default_pattern)

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
    :ok = RingLogger.attach(io: io, format: @default_pattern)
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
    :ok = RingLogger.attach(io: io, format: @default_pattern)
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
    :ok = RingLogger.attach(io: io, format: @default_pattern)
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
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    handshake_log(io, :debug, "Hello")

    buffer = RingLogger.get()
    assert [%{level: :debug, message: "Hello"}] = buffer
  end

  test "buffer does not exceed size", %{io: io} do
    RingLogger.configure(max_size: 2)
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    handshake_log(io, :debug, "Foo")

    buffer = RingLogger.get()
    assert [%{level: :debug, message: "Foo"}] = buffer

    handshake_log(io, :debug, "Bar")

    buffer = RingLogger.get()

    assert [
             %{level: :debug, message: "Foo"},
             %{level: :debug, message: "Bar"}
           ] = buffer

    handshake_log(io, :debug, "Baz")

    buffer = RingLogger.get()

    assert [
             %{level: :debug, message: "Bar"},
             %{level: :debug, message: "Baz"}
           ] = buffer
  end

  test "buffer can be fetched by range", %{io: io} do
    RingLogger.configure(max_size: 3)
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")
    |> handshake_log(:debug, "Baz")

    buffer = RingLogger.get(2)
    assert [%{level: :debug, message: "Baz"}] = buffer
    buffer = RingLogger.get(1)

    assert [
             %{level: :debug, message: "Bar"},
             %{level: :debug, message: "Baz"}
           ] = buffer
  end

  test "next supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:info, "Hello")
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    :ok =
      RingLogger.next(
        pager: fn device, msg ->
          IO.write(device, "Got #{String.length(IO.chardata_to_string(msg))} characters")
        end
      )

    assert_receive {:io, messages}

    assert messages =~ "Got"
  end

  test "tail supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

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

    assert messages =~ "Got"
  end

  test "grep supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)

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

    assert messages =~ "Got"
  end

  test "buffer start index is less then buffer_start_index", %{io: io} do
    RingLogger.configure(max_size: 1)

    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    buffer = RingLogger.get(0)
    assert [%{level: :debug, message: "Bar"}] = buffer
  end

  test "receive nothing when fetching buffer out of range" do
    assert [] = RingLogger.get(100)
  end

  test "buffer can be paged", %{io: io} do
    RingLogger.configure(max_size: 3)
    :ok = RingLogger.attach(io: io, format: @default_pattern)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")
    |> handshake_log(:debug, "Baz")

    buffer = RingLogger.get(1, 1)
    assert [%{level: :debug, message: "Bar"}] = buffer

    buffer = RingLogger.get(1, 2)

    assert [
             %{level: :debug, message: "Bar"},
             %{level: :debug, message: "Baz"}
           ] = buffer

    buffer = RingLogger.get(1, 3)

    assert [
             %{level: :debug, message: "Bar"},
             %{level: :debug, message: "Baz"}
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
    :ok =
      RingLogger.attach(
        io: io,
        format: {RingLogger.TestCustomFormatter, :format},
        metadata: [:index]
      )

    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "index=0 Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "index=1 World"
  end

  test "can filter levels by module", %{io: io} do
    :ok =
      RingLogger.attach(io: io, module_levels: %{__MODULE__ => :info}, format: @default_pattern)

    Logger.info("foo")
    assert_receive {:io, _message}
    Logger.debug("bar")
    refute_receive {:io, _message}
    Logger.warning("baz")
    assert_receive {:io, _message}
  end

  test "can filter all levels by module", %{io: io} do
    :ok =
      RingLogger.attach(io: io, module_levels: %{__MODULE__ => :none}, format: @default_pattern)

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
    :ok =
      RingLogger.attach(
        io: io,
        module_levels: %{__MODULE__ => :debug},
        level: :warning,
        format: @default_pattern
      )

    Logger.debug("Hello world")
    assert_receive {:io, _message}
  end

  test "can filter module level with grep", %{io: io} do
    :ok =
      RingLogger.attach(io: io, module_levels: %{__MODULE__ => :info}, format: @default_pattern)

    handshake_log(io, :info, "Hello")

    RingLogger.grep(~r/H..lo/, io: io, colors: [enabled: false])
    assert_receive {:io, message}
    assert String.contains?(message, "[info] Hello")
  end

  test "can save to a file", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
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
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    handshake_log(io, :debug, "Hello")

    # This better not exist...
    assert {:error, :enoent} == RingLogger.save("/a/b/c/d/e/f/g")
  end

  test "logging chardata", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    Logger.info(~c"Cześć!")
    assert_receive {:io, message}
    assert message =~ "[info] Cześć!"
  end

  test "logging corrupt data", %{io: io} do
    # This is non-Unicode and shouldn't crash RingLogger. There are slightly
    # different paths that are taken for iodata vs binary data, so make sure
    # they behave identically.
    message_string = <<227, 97, 195, 253, 123, 50, 91, 116, 114, 227, 110>>
    message_iodata = [message_string]

    :ok = RingLogger.attach(io: io, format: @default_pattern)
    Logger.debug(message_string)
    assert_receive {:io, message_string_result}

    Logger.debug(message_iodata)
    assert_receive {:io, message_iodata_result}

    assert String.valid?(message_string_result)
    assert String.valid?(message_iodata_result)

    assert message_string_result =~ "{2[tr"
    assert message_iodata_result =~ "{2[tr"
  end

  describe "fetching config" do
    test "can retrieve config for attached client", %{io: io} do
      :ok = RingLogger.attach(io: io, format: @default_pattern)

      got = RingLogger.config() |> Map.new()

      assert got[:io] == io
      assert got[:level] == :debug
      assert got[:metadata] == []
      assert got[:module_levels] == %{}
      assert got[:colors][:debug] == :cyan
      assert got[:colors][:info] == :normal
      assert got[:colors][:warning] == :yellow
      assert got[:colors][:error] == :red
    end

    test "returns error when no attached client" do
      assert RingLogger.config() == {:error, :no_client}
    end
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
