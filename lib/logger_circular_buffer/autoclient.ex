defmodule LoggerCircularBuffer.Autoclient do
  alias LoggerCircularBuffer.Client

  @moduledoc """
  This is a helper module for Client that makes it easy to use at the IEx prompt by removing
  the need to keep track of pids.
  """

  @doc """
  """
  def attach(config \\ []) do
    Client.attach(maybe_create_client(config))
  end

  def detach() do
    case get_client_pid() do
      nil -> :ok
      pid -> Client.detach(pid)
    end
  end

  def forget() do
    client_pid = Process.delete(:logger_circular_buffer_client)

    if client_pid do
      Client.stop(client_pid)
    end
  end

  def tail(config \\ []) do
    Client.tail(maybe_create_client(config))
  end

  def reset() do
    Client.reset(maybe_create_client())
  end

  def format(message) do
    Client.format(maybe_create_client(), message)
  end

  defp maybe_create_client(config \\ []) do
    case get_client_pid() do
      nil ->
        {:ok, pid} = Client.start_link(config)
        Process.put(:logger_circular_buffer_client, pid)
        pid

      pid ->
        pid
    end
  end

  defp get_client_pid() do
    Process.get(:logger_circular_buffer_client)
  end
end
