defmodule RingLogger.Autoclient do
  alias RingLogger.Client

  @moduledoc """
  Helper module for `RingLogger.Client` to simplify IEx use

  If you're a human, call these functions via `RingLogger.*`. If you're a
  program, call `RingLogger.Client.start_link/1` to start you're own client and
  call it directly.
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
  Completely stop the RingLogger.Client. You normally don't need to run this.
  """
  def forget() do
    client_pid = Process.delete(:ring_logger_client)

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
  Run a regular expression on each entry in the log and print out the matchers.
  """
  def grep(regex, config \\ []) do
    with :ok <- check_server_started(),
         pid <- maybe_create_client(config),
         do: Client.grep(pid, regex)
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
  Format a log message. This is useful if you're calling `RingLogger.get/1` directly.
  """
  def format(message) do
    with :ok <- check_server_started(),
         pid <- maybe_create_client(),
         do: Client.format(pid, message)
  end

  defp check_server_started() do
    if !Process.whereis(RingLogger.Server) do
      IO.puts("""
      The RingLogger backend isn't running. Going to try starting it, but don't
      expect any log entries before now.

      To start it in the future, add the following to your config.exs:

        config :logger, backends: [RingLogger]

      or start it manually:

        iex> Logger.add_backend(RingLogger)
      """)

      try_adding_backend()
    else
      :ok
    end
  end

  defp try_adding_backend() do
    case Logger.add_backend(RingLogger) do
      {:ok, _} ->
        :ok

      error ->
        IO.puts("""

        Error trying to start the logger. Check your configuration
        and try again.

        """)

        error
    end
  end

  defp maybe_create_client(config \\ []) do
    case get_client_pid() do
      nil ->
        {:ok, pid} = Client.start_link(config)
        Process.put(:ring_logger_client, pid)
        pid

      pid ->
        # Update the configuration if the user changed something
        Client.configure(pid, config)
        pid
    end
  end

  defp get_client_pid() do
    Process.get(:ring_logger_client)
  end
end
