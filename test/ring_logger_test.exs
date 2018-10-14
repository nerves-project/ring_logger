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
    Logger.debug("Hello")
    Logger.debug("World")
    RingLogger.grep(~r/H..lo/, io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can grep iodata in log", %{io: io} do
    Logger.debug(["Hello", ",", ' world'])
    Logger.debug("World")
    RingLogger.grep(~r/H..lo/, io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello, world"
  end

  test "can next the log", %{io: io} do
    Logger.debug("Hello")
    :ok = RingLogger.next(io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    Logger.debug("Foo")
    Logger.debug("Bar")
    :ok = RingLogger.next()
    assert_receive {:io, message1}
    assert_receive {:io, message2}

    assert message1 =~ "[debug] Foo"
    assert message2 =~ "[debug] Bar"
  end

  test "can reset to the beginning", %{io: io} do
    Logger.debug("Hello")
    :ok = RingLogger.next(io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    :ok = RingLogger.reset()
    :ok = RingLogger.next()
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can tail the log", %{io: io} do
    :ok = RingLogger.tail(io: io)
    refute_receive {:io, _}

    Logger.debug("Hello")
    :ok = RingLogger.tail()
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    Logger.debug("Foo")
    Logger.debug("Bar")
    :ok = RingLogger.tail()
    assert_receive {:io, message1}
    assert_receive {:io, message2}
    assert_receive {:io, message3}

    assert message1 =~ "[debug] Hello"
    assert message2 =~ "[debug] Foo"
    assert message3 =~ "[debug] Bar"

    :ok = RingLogger.tail(1)
    assert_receive {:io, message}
    assert message =~ "[debug] Bar"
  end

  test "can get buffer", %{io: io} do
    :ok = RingLogger.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Hello", _, _}}] = buffer

    formatted_message =
      buffer
      |> List.first()
      |> RingLogger.format()
      |> IO.iodata_to_binary()

    assert formatted_message == message
  end

  test "buffer does not exceed size", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 2)
    :ok = RingLogger.attach(io: io)

    Logger.debug("Foo")
    assert_receive {:io, _message}
    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Foo", _, _}}] = buffer

    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Foo", _, _}}, {:debug, {Logger, "Bar", _, _}}] = buffer

    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = RingLogger.get()
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer can be fetched by range", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 3)
    :ok = RingLogger.attach(io: io)
    Logger.debug("Foo")
    assert_receive {:io, _message}
    Logger.debug("Bar")
    assert_receive {:io, _message}
    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = RingLogger.get(2)
    assert [{:debug, {Logger, "Baz", _, _}}] = buffer
    buffer = RingLogger.get(1)
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer start index is less then buffer_start_index", %{io: io} do
    Logger.configure_backend(RingLogger, max_size: 1)
    :ok = RingLogger.attach(io: io)
    Logger.debug("Foo")
    assert_receive {:io, _message}
    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = RingLogger.get(0)
    assert [{:debug, {Logger, "Bar", _, _}}] = buffer
  end

  test "receive nothing when fetching buffer out of range" do
    assert [] = RingLogger.get(100)
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

    Logger.info("Hello")
    RingLogger.grep(~r/H..lo/, io: io)
    assert_receive {:io, message}
    assert String.contains?(message, "[info]  Hello")
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
