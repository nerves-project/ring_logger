defmodule RingLoggerTest do
  use ExUnit.Case, async: false
  doctest RingLogger

  import ExUnit.CaptureIO
  require Logger
  alias RingLogger.TestCustomFormatter

  setup do
    {:ok, pid} = RingLogger.TestIO.start(self())
    Logger.remove_backend(:console)

    # Flush any latent messages in the Logger to avoid them polluting
    # our tests
    Logger.flush()

    Logger.add_backend(RingLogger)
    Logger.configure_backend(RingLogger, max_size: 10)

    on_exit(fn ->
      RingLogger.TestIO.stop(pid)
      Logger.remove_backend(RingLogger)
    end)

    {:ok, [io: pid]}
  end

  @doc """
  Ensure that a log message makes it way through the logger processes.

  The RingLogger needs to be attached for this to work. This makes
  logging synchronous so that we can test tail, next, grep, etc. that
  rely on the messages being received by RingLogger.
  """
  def handshake_log(io, level, message) do
    Logger.log(level, message)
    assert_receive {:io, msg}
    assert String.contains?(msg, to_string(level))

    flattened_message = IO.iodata_to_binary(message)
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

    RingLogger.grep(~r/H..lo/, io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can grep iodata in log", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, ["Hello", ",", ' world'])
    |> handshake_log(:debug, "World")

    RingLogger.grep(~r/H..lo/, io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello, world"
  end

  test "can grep using a string", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Hello")
    |> handshake_log(:debug, "World")

    RingLogger.grep("H..lo", io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
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
    assert [{:debug, {Logger, "Hello", _, _}}] = buffer
  end

  test "buffer does not exceed size", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 2)
    :ok = RingLogger.attach(io: io)

    handshake_log(io, :debug, "Foo")

    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Foo", _, _}}] = buffer

    handshake_log(io, :debug, "Bar")

    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Foo", _, _}}, {:debug, {Logger, "Bar", _, _}}] = buffer

    handshake_log(io, :debug, "Baz")

    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer can be fetched by range", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 3)
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")
    |> handshake_log(:debug, "Baz")

    buffer = RingLogger.get(2)
    assert [{:debug, {Logger, "Baz", _, _}}] = buffer
    buffer = RingLogger.get(1)
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "next supports passing a custom pager", %{io: io} do
    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:info, "Hello")
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    # Even thought the intention for a custom pager is to "page" the output to the user,
    # just print out the number of characters as a check that the custom function is
    # actually run.
    :ok =
      RingLogger.next(
        pager: fn device, msg ->
          IO.write(device, "Got #{String.length(IO.iodata_to_binary(msg))} characters")
        end
      )

    assert_receive {:io, messages}

    assert messages =~ "Got 139 characters"
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
          IO.write(device, "Got #{String.length(IO.iodata_to_binary(msg))} characters")
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
          IO.write(device, "Got #{String.length(IO.iodata_to_binary(msg))} characters")
        end
      )

    assert_receive {:io, messages}

    assert messages =~ "Got 70 characters"
  end

  test "buffer start index is less then buffer_start_index", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 1)

    :ok = RingLogger.attach(io: io)

    io
    |> handshake_log(:debug, "Foo")
    |> handshake_log(:debug, "Bar")

    buffer = RingLogger.get(0)
    assert [{:debug, {Logger, "Bar", _, _}}] = buffer
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
    assert [{:debug, {Logger, "Bar", _, _}}] = buffer
    buffer = RingLogger.get(1, 2)
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
    buffer = RingLogger.get(1, 3)
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
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
    Logger.warn("baz")
    assert_receive {:io, _message}
  end

  test "can filter all levels by module", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :none})

    Logger.info("foo")
    refute_receive {:io, _message}
    Logger.debug("bar")
    refute_receive {:io, _message}
    Logger.warn("baz")
    refute_receive {:io, _message}
    Logger.error("uhh")
    refute_receive {:io, _message}
  end

  test "can filter module level to print lower than logger level", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :debug}, level: :warn)

    Logger.debug("Hello world")
    assert_receive {:io, _message}
  end

  test "can filter module level with grep", %{io: io} do
    :ok = RingLogger.attach(io: io, module_levels: %{__MODULE__ => :info})
    handshake_log(io, :info, "Hello")

    RingLogger.grep(~r/H..lo/, io: io)
    assert_receive {:io, message}
    assert String.contains?(message, "[info]  Hello")
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

  describe "fetching config" do
    test "can retrieve config for attached client", %{io: io} do
      :ok = RingLogger.attach(io: io)

      config = [
        colors: %{debug: :cyan, enabled: true, error: :red, info: :normal, warn: :yellow},
        format: ["\n", :time, " ", :metadata, "[", :level, "] ", :levelpad, :message, "\n"],
        io: io,
        level: :debug,
        metadata: [],
        module_levels: %{}
      ]

      assert RingLogger.config() == config
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
