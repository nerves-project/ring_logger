defmodule RingLogger.Autoclient do
  @moduledoc """
  Helper module for `RingLogger.Client` to simplify IEx use

  If you're a human, call these functions via `RingLogger.*`. If you're a
  program, call `RingLogger.Client.start_link/1` to start your own client and
  call it directly.
  """

  alias RingLogger.Client

  @doc """
  Attach to the logger and print messages as they come in.
  """
  @spec attach(RingLogger.client_options()) :: :ok | {:error, term()}
  def attach(opts \\ []) when is_list(opts) do
    run(&Client.attach/1, opts)
  end

  @doc """
  Fetch the current configuration for the attached client.
  """
  @spec config() :: RingLogger.client_options() | {:error, term()}
  def config() do
    case get_client_pid() do
      nil -> {:error, :no_client}
      client -> Client.config(client)
    end
  end

  @doc """
  Detach from the logger. Log messages will stop being printed to the console.
  """
  @spec detach() :: :ok
  def detach() do
    case get_client_pid() do
      nil -> :ok
      pid -> Client.detach(pid)
    end
  end

  @doc """
  Completely stop the RingLogger.Client. You normally don't need to run this.
  """
  @spec forget() :: :ok
  def forget() do
    case Process.delete(:ring_logger_client) do
      nil -> :ok
      client_pid -> Client.stop(client_pid)
    end
  end

  @doc """
  Print the log messages since the previous time this was called.
  """
  @spec next(RingLogger.client_options()) :: :ok | {:error, term()}
  def next(opts \\ []) when is_list(opts) do
    run(&Client.next(&1, opts), opts)
  end

  @doc """
  Print the log message count since the previous time this was called.
  """
  @spec count_next(RingLogger.client_options()) :: non_neg_integer()
  def count_next(opts \\ []) when is_list(opts) do
    run(&Client.count_next/1, opts)
  end

  @doc """
  Print the most recent log messages.
  """
  @spec tail(non_neg_integer(), RingLogger.client_options()) :: :ok
  def tail(n, opts) when is_integer(n) and is_list(opts) do
    run(&Client.tail(&1, n, opts), opts)
  end

  @doc """
  Run a regular expression on each entry in the log and print out the matchers.
  """
  @spec grep(String.t() | Regex.t(), RingLogger.client_options()) :: :ok | {:error, term()}
  def grep(regex_or_string, opts \\ []) when is_list(opts) do
    run(&Client.grep(&1, regex_or_string, opts), opts)
  end

  @doc """
  Return a list of formatted log entries that match the given metadata key-value pair.
  """
  @spec grep_metadata(atom(), String.t() | Regex.t()) :: :ok | {:error, term()}
  def grep_metadata(key, match_value) do
    run(&Client.grep_metadata(&1, key, match_value, []), [])
  end

  @doc """
  Reset the index used to keep track of the position in the log for `tail/1` so
  that the next call to `tail/1` starts back at the oldest entry.
  """
  @spec reset(RingLogger.client_options()) :: :ok | {:error, term()}
  def reset(opts \\ []) when is_list(opts) do
    run(&Client.reset/1, opts)
  end

  @doc """
  Format a log message. This is useful if you're calling `RingLogger.get/1` directly.
  """
  @spec format(RingLogger.entry()) :: :ok | {:error, term()}
  def format(message) do
    run(&Client.format(&1, message), [])
  end

  @doc """
  Save the log.
  """
  @spec save(Path.t()) :: :ok | {:error, term()}
  def save(path) do
    run(&Client.save(&1, path), [])
  end

  defp run(fun, opts) do
    with :ok <- check_server_started() do
      pid = maybe_create_client(opts)
      fun.(pid)
    end
  end

  defp check_server_started() do
    if Process.whereis(RingLogger.Server) == nil do
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

  defp maybe_create_client(opts) do
    case get_client_pid() do
      nil ->
        {:ok, pid} = Client.start_link(opts)
        Process.put(:ring_logger_client, pid)
        pid

      pid ->
        # Update the configuration if the user changed something
        Client.configure(pid, opts)
        pid
    end
  end

  defp get_client_pid() do
    Process.get(:ring_logger_client)
  end
end
