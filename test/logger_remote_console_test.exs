defmodule Logger.RemoteConsoleTest do
  use ExUnit.Case
  doctest Logger.RemoteConsole

  import ExUnit.CaptureIO
  alias Logger.RemoteConsole.{Server, Client}
  require Logger

  setup do
    {:ok, pid} = Logger.RemoteConsole.TestIO.start(self())
    Logger.remove_backend(:console)
    Logger.add_backend(Logger.RemoteConsole)
    Logger.configure_backend(Logger.RemoteConsole, buffer_size: 10)
    on_exit fn ->
      Logger.RemoteConsole.TestIO.stop(pid)
    end
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

  test "can flush buffer", %{io: io} do
    Server.attach(io: io)
    Logger.flush()
    assert Server.get_buffer() == []
    Logger.debug("Hi")
    assert_receive {:io, _message}
    Logger.flush()
    assert Server.get_buffer() == []
  end

  test "can get buffer", %{io: io} do
    {:ok, client} = Server.attach(io: io)
    Server.flush_buffer()
    Logger.debug("Hello")
    assert_receive {:io, message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Hello", _, _}}] = buffer
    formatted_message = 
      buffer
      |> List.first
      |> Client.format_message(client.config)
    assert formatted_message == message
  end

  test "buffer does not exceed size", %{io: io} do
    Logger.configure_backend(Logger.RemoteConsole, buffer_size: 2)
    Server.attach(io: io)
    Server.flush_buffer()

    Logger.debug("Foo")
    assert_receive {:io, _message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Foo", _, _}}] = buffer

    Logger.debug("Bar")
    assert_receive {:io, _message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Foo", _, _}},
            {:debug, {Logger, "Bar", _, _}}] = buffer

    Logger.debug("Baz")
    assert_receive {:io, _message}
    buffer = Server.get_buffer()
    assert [{:debug, {Logger, "Bar", _, _}},
            {:debug, {Logger, "Baz", _, _}}] = buffer
    
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
