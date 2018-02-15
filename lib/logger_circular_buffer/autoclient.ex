defmodule LoggerCircularBuffer.Autoclient do
  alias LoggerCircularBuffer.Client

  @moduledoc """
  This is a helper module for LoggerCircularBuffer.Client that makes it easy to use at the IEx prompt by removing
  the need to keep track of pids. Programs should normally call LoggerCircularBuffer.Client directly to avoid
  many of the automatic behaviors that this module adds.
  """

  @doc """
  Attach to the logger and print messages as they come in.
  """
  def attach(config \\ []) do
    with :ok <- check_server_started(),
         pid <- maybe_create_client(config),
         do: Client.attach(pid)
  end

  @doc """
  Detach from the logger. Log messages will stop being printed to the console.
  """
  def detach() do
    case get_client_pid() do
      nil -> :ok
      pid -> Client.detach(pid)
    end
  end

  @doc """
  Completely stop the LoggerCircularBuffer.Client. You normally don't need to run this.
  """
  def forget() do
    client_pid = Process.delete(:logger_circular_buffer_client)
    if client_pid do
      Client.stop(client_pid)
    end
  end

  @doc """
  Print all log messages since the previous time this was called.
  """
  def tail(config \\ []) do
    with :ok <- check_server_started(),
         pid <- maybe_create_client(config),
         do: Client.tail(pid)
  end

  @doc """
  Reset the index used to keep track of the position in the log for `tail/1` so
  that the next call to `tail/1` starts back at the oldest entry.
  """
  def reset(config \\ []) do
    with :ok <- check_server_started(),
         pid <- maybe_create_client(config),
         do: Client.reset(pid)
  end

  @doc """
  Format a log message. This is useful if you're calling `LoggerCircularBuffer.get/1` directly.
  """
  def format(message) do
    with :ok <- check_server_started(),
         pid <- maybe_create_client(),
         do: Client.format(pid, message)
  end

  defp check_server_started() do
    if !Process.whereis(LoggerCircularBuffer.Server) do
      IO.puts("""
      The LoggerCircularBuffer backend isn't running. Please start it by adding the following to your config.exs:

        config :logger, backends: [LoggerCircularBuffer]

      or start it manually:

        iex> Logger.add_backend(LoggerCircularBuffer)
      """)

      {:error, :not_started}
    else
      :ok
    end
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
