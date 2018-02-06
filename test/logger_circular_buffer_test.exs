defmodule Logger.CircularBufferTest do
  use ExUnit.Case, async: false
  doctest Logger.CircularBuffer

  import ExUnit.CaptureIO
  alias Logger.CircularBuffer.{Server, Client}
  require Logger

  setup do
    {:ok, pid} = Logger.CircularBuffer.TestIO.start(self())
    Logger.remove_backend(:console)
    Logger.add_backend(Logger.CircularBuffer)
    Logger.configure_backend(Logger.CircularBuffer, buffer_size: 10)

    on_exit(fn ->
      Logger.CircularBuffer.TestIO.stop(pid)
      Logger.remove_backend(Logger.CircularBuffer)
      Process.whereis(Server)
      |> Process.exit(:kill)
    end)

    {:ok, [io: pid]}
  end

  test "can attach", %{io: io} do
    Server.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
  end

  test "output is not duplicated on group leader", %{io: io} do
    Server.attach(io: io)

    output =
      capture_log(fn ->
        Logger.debug("Hello")
      end)

    assert output == ""
  end

  test "can receive multiple messages", %{io: io} do
    Server.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "[debug] World"
  end

  test "can detach", %{io: io} do
    Server.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "[debug] Hello"
    Server.detach()
    Logger.debug("World")
    refute_receive {:io, _}
  end

  test "can get buffer", %{io: io} do
    {:ok, client} = Server.attach(io: io)
    Logger.debug("Hello")
    assert_receive {:io, message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Hello", _, _}}] = buffer

    formatted_message =
      buffer
      |> List.first()
      |> Client.format_message(client.config)
      |> IO.iodata_to_binary()

    assert formatted_message == message
  end

  test "buffer does not exceed size", %{io: io} do
    Logger.configure_backend(Logger.CircularBuffer, buffer_size: 2)
    Server.attach(io: io)

    Logger.debug("Foo")
    assert_receive {:io, _message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Foo", _, _}}] = buffer

    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Foo", _, _}}, {:debug, {Logger, "Bar", _, _}}] = buffer

    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer can be fetched by range", %{io: io} do
    Logger.configure_backend(Logger.CircularBuffer, buffer_size: 3)
    Server.attach(io: io)
    Logger.debug("Foo")
    assert_receive {:io, _message}
    Logger.debug("Bar")
    assert_receive {:io, _message}
    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = Server.get_buffer(2)
    assert [{:debug, {Logger, "Baz", _, _}}] = buffer
    buffer = Server.get_buffer(1)
    assert [{:debug, {Logger, "Bar", _, _}}, {:debug, {Logger, "Baz", _, _}}] = buffer
  end

  test "buffer start index is less then buffer_start_index", %{io: io} do
    Logger.configure_backend(Logger.CircularBuffer, buffer_size: 1)
    Server.attach(io: io)
    Logger.debug("Foo")
    assert_receive {:io, _message}
    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = Server.get_buffer(0)
    assert [{:debug, {Logger, "Bar", _, _}}] = buffer
  end

  test "can format messages", %{io: io} do
    Server.attach(io: io, format: "$metadata$message", metadata: [:index])
    Logger.debug("Hello")
    assert_receive {:io, message}
    assert message =~ "index=1 Hello"
    Logger.debug("World")
    assert_receive {:io, message}
    assert message =~ "index=2 World"
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
