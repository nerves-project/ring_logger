defmodule LoggerCircularBufferTest do
  use ExUnit.Case, async: false
  doctest LoggerCircularBuffer

  import ExUnit.CaptureIO
  require Logger

  setup do
    {:ok, pid} = LoggerCircularBuffer.TestIO.start(self())
    Logger.remove_backend(:console)

    # Flush any latent messages in the Logger to avoid them polluting
    # our tests
    Logger.flush()

    Logger.add_backend(LoggerCircularBuffer)
    Logger.configure_backend(LoggerCircularBuffer, max_size: 10)

    on_exit(fn ->
      LoggerCircularBuffer.TestIO.stop(pid)
      Logger.remove_backend(LoggerCircularBuffer)
    end)

    {:ok, [io: pid]}
  end

  test "can attach", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "attaching twice doesn't duplicate messages", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    refute_receive {:io, _}
  end

  test "attach, detach, attach works", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)
    :ok = LoggerCircularBuffer.detach()
    :ok = LoggerCircularBuffer.attach(io: io)
  end

  test "output is not duplicated on group leader", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)

    output =
      capture_log(fn ->
        Logger.debug("Hello")
      end)

    assert output == ""
  end

  test "can receive multiple messages", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "[debug] World"
  end

  test "can detach", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    LoggerCircularBuffer.detach()
    Logger.debug("World")
    refute_receive {:io, _}
  end

  test "can tail the log", %{io: io} do
    Logger.debug("Hello")
    :ok = LoggerCircularBuffer.tail(io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    Logger.debug("Foo")
    Logger.debug("Bar")
    :ok = LoggerCircularBuffer.tail()
    assert_receive {:io, message1}
    assert_receive {:io, message2}

    assert message1 =~ "[debug] Foo"
    assert message2 =~ "[debug] Bar"
  end

  test "can reset to the beginning", %{io: io} do
    Logger.debug("Hello")
    :ok = LoggerCircularBuffer.tail(io: io)
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"

    :ok = LoggerCircularBuffer.reset()
    :ok = LoggerCircularBuffer.tail()
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "can get buffer", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    buffer = LoggerCircularBuffer.get()
    assert [{:debug, {Logger, "Hello", _, _}}] = buffer

    formatted_message =
      buffer
      |> List.first()
      |> LoggerCircularBuffer.format()
      |> IO.iodata_to_binary()

    assert formatted_message == message
  end

  test "buffer does not exceed size", %{io: io} do
    Logger.configure_backend(LoggerCircularBuffer, max_size: 2)
    :ok = LoggerCircularBuffer.attach(io: io)

    Logger.debug("Foo")
    assert_receive {:io, _message}
    buffer = LoggerCircularBuffer.get()
    assert [{:debug, {Logger, "Foo", _, _}}] = buffer

    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = LoggerCircularBuffer.get()
    assert [{:debug, {Logger, "Foo", _, _}}, {:debug, {Logger, "Bar", _, _}}] = buffer

    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = LoggerCircularBuffer.get()
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer can be fetched by range", %{io: io} do
    Logger.configure_backend(LoggerCircularBuffer, max_size: 3)
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Foo")
    assert_receive {:io, _message}
    Logger.debug("Bar")
    assert_receive {:io, _message}
    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = LoggerCircularBuffer.get(2)
    assert [{:debug, {Logger, "Baz", _, _}}] = buffer
    buffer = LoggerCircularBuffer.get(1)
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer start index is less then buffer_start_index", %{io: io} do
    Logger.configure_backend(LoggerCircularBuffer, max_size: 1)
    :ok = LoggerCircularBuffer.attach(io: io)
    Logger.debug("Foo")
    assert_receive {:io, _message}
    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = LoggerCircularBuffer.get(0)
    assert [{:debug, {Logger, "Bar", _, _}}] = buffer
  end

  test "receive nothing when fetching buffer out of range" do
    assert [] = LoggerCircularBuffer.get(100)
  end

  test "can format messages", %{io: io} do
    :ok = LoggerCircularBuffer.attach(io: io, format: "$metadata$message", metadata: [:index])

    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "index=0 Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "index=1 World"
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
