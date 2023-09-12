defmodule RingLogger do
  @moduledoc """
  This is an in-memory ring buffer backend for the Elixir Logger.

  Install it by adding it to your `config.exs`:

  ```elixir
  use Mix.Config

  # Add the RingLogger backend. This removes the default :console backend.
  config :logger, backends: [RingLogger]

  # Periodically save logs to a file, and load logs on GenServer start from this file
  config :logger, RingLogger, persist_path: "./myapp.log", persist_seconds: 300

  # Save messages to one circular buffer that holds 1024 entries.
  config :logger, RingLogger, max_size: 1024

  # Separate out `:error` and `:warning` messages to their own circular buffer.
  # All other log messages are stored in the default circular buffer.
  config :logger, RingLogger, buffers: %{
    errors: %{
      levels: [:error, :warning],
      max_size: 1024
    }
  }

  # Specify circular buffers for all log levels. The default circular buffer won't
  # be used in this example configuration.
  config :logger, RingLogger, buffers: %{
    low_priority: %{
      levels: [:warning, :notice, :info, :debug],
      max_size: 1024
    },
    high_priority: %{
      levels: [:emergency, :alert, :critical, :error],
      max_size: 1024
    }
  }
  ```

  Or add manually:

  ```elixir
  Logger.add_backend(RingLogger)
  Logger.configure_backend(RingLogger, max_size: 1024)
  ```

  Once added as a backend, you have two options depending on whether you're
  accessing the `RingLogger` via the IEx prompt or via code.  If you're at the
  IEx prompt, use the helper methods in here like `attach`, `detach`, `next`,
  `tail`, `grep`, etc. They'll automate a few things behind the scenes. If
  you're writing a program that needs to get log messages, use `get` or
  `start_link` a `RingLogger.Client` and call its methods directly.
  """
  @behaviour :gen_event

  alias RingLogger.Autoclient
  alias RingLogger.Server

  @typedoc "Option values used by the ring logger"
  @type server_option() ::
          {:max_size, pos_integer()}
          | {:buffers, %{term() => buffer()}}
          | {:persist_path, String.t()}
          | {:persist_seconds, pos_integer()}

  @typedoc "Options to define a separate buffer based on log levels"
  @type buffer() :: %{levels: [Logger.level()], max_size: pos_integer()}

  @typedoc "Callback function for printing/paging tail, grep, and next output"
  @type pager_fun() :: (IO.device(), IO.chardata() -> :ok | {:error, term()})

  @typedoc "Option values used by client-side functions like `attach` and `tail`"
  @type client_option() ::
          {:io, term}
          | {:pager, pager_fun()}
          | {:color, term}
          | {:metadata, Logger.metadata()}
          | {:format, String.t() | custom_formatter}
          | {:level, Logger.level()}
          | {:module_levels, map()}
          | {:application_levels, map()}

  @typedoc "Option list for client-side functions"
  @type client_options() :: [client_option()]

  @typedoc "A map holding a raw, unformatted log entry"
  @type entry() :: %{
          level: Logger.level(),
          module: module(),
          message: Logger.message(),
          # Logger.Formatter.date_time_ms() in Elixir 1.15 and Logger.Formatter.time() in earlier versions
          timestamp: {{1970..10000, 1..12, 1..31}, {0..23, 0..59, 0..59, 0..999}},
          metadata: Logger.metadata()
        }

  @typep custom_formatter() :: {module, function}

  #
  # API
  #

  @doc """
  Attach the current IEx session to the logger. It will start printing log messages.

  Options include:

  * `:io` - output location when printing. Defaults to `:stdio`
  * `:colors` - a keyword list of coloring options
  * `:metadata` - a keyword list of additional metadata
  * `:format` - the format message used to print logs
  * `:level` - the minimum log level to report by this backend. Note that the `:logger`
    application's `:level` setting filters log messages prior to `RingLogger`.
  * `:module_levels` - a map of log level overrides per module. For example,
    %{MyModule => :error, MyOtherModule => :none}
  * `:application_levels` - a map of log level overrides per application. For example,
    %{:my_app => :error, :my_other_app => :none}. Note log levels set in `:module_levels`
    will take precedence.
  """
  @spec attach(client_options()) :: :ok | {:error, :no_client}
  defdelegate attach(opts \\ []), to: Autoclient

  @doc """
  Fetch the current configuration for the attached client
  """
  @spec config() :: client_options() | {:error, :no_client}
  defdelegate config(), to: Autoclient

  @doc """
  Detach the current IEx session from the logger
  """
  @spec detach() :: :ok
  defdelegate detach(), to: Autoclient

  @doc """
  Print the next messages in the log

  Options include:

  * Options from `attach/1`
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.binwrite/2`.
  """
  @spec next(client_options()) :: :ok | {:error, term()}
  defdelegate next(opts \\ []), to: Autoclient

  @doc """
  Count the next messages in the log

  NOTE: This function may change in future releases.

  Options include:

  * Options from `attach/1`
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.binwrite/2`.
  """
  @spec count_next(client_options()) :: non_neg_integer()
  defdelegate count_next(opts \\ []), to: Autoclient

  @doc """
  Save the contents of the log to the specified path

  The file is overwritten if it already exists. Log message
  formatting is done similarly to other RingLogger calls.
  """
  @spec save(Path.t()) :: :ok | {:error, term()}
  defdelegate save(path), to: Autoclient

  @doc """
  Print the last 10 messages
  """
  @spec tail() :: :ok
  def tail(), do: Autoclient.tail(10, [])

  @doc """
  Print the last messages in the log

  See `tail/2`.
  """

  @spec tail(non_neg_integer() | client_options()) :: :ok
  def tail(opts) when is_list(opts), do: Autoclient.tail(10, opts)
  def tail(n) when is_integer(n), do: Autoclient.tail(n, [])

  @doc """
  Print the last n messages in the log

  Options include:

  * Options from `attach/1`
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.binwrite/2`.
  """
  @spec tail(non_neg_integer(), client_options()) :: :ok
  def tail(n, opts), do: Autoclient.tail(n, opts)

  @doc """
  Reset the index into the log for `next/1` to the oldest entry.
  """
  @spec reset(client_options()) :: :ok | {:error, term()}
  defdelegate reset(opts \\ []), to: Autoclient

  @doc """
  Run a regular expression on each entry in the log and print out the matchers.

  For example:

  iex> RingLogger.grep(~r/something/)
  :ok

    Options include:

  * Options from `attach/1`
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.binwrite/2`.
  * `:before` - Number of lines before the match to include
  * `:after` - NUmber of lines after the match to include
  """
  @spec grep(Regex.t() | String.t(), client_options()) :: :ok | {:error, term()}
  defdelegate grep(regex_or_string, opts \\ []), to: Autoclient

  @doc """
  Return a list of formatted log entries that match the given metadata key-value pair.

  For example:

  iex> RingLogger.grep_metadata(:session_id, "abc")
  :ok

  iex> RingLogger.grep_metadata(:session_id, ~r/something/)
  :ok
  """
  @spec grep_metadata(atom(), String.t() | Regex.t()) :: :ok | {:error, term()}
  defdelegate grep_metadata(key, match_value), to: Autoclient

  @doc """
  Helper method for formatting log messages per the current client's
  configuration.
  """
  @spec format(entry()) :: :ok | {:error, :no_client}
  defdelegate format(message), to: Autoclient

  @doc """
  Get n log messages starting at the specified index.

  Set n to 0 to get entries to the end
  """
  @spec get(non_neg_integer(), non_neg_integer()) :: [entry()]
  defdelegate get(index \\ 0, n \\ 0), to: Server

  @doc """
  Update the logger configuration.

  Options include:
  * `:max_size` - the max number of log messages to store at a time
  """
  @spec configure([server_option]) :: :ok
  defdelegate configure(opts), to: Server

  #
  # Logger backend callbacks
  #
  @impl :gen_event
  def init(__MODULE__) do
    init({__MODULE__, []})
  end

  @spec init({module(), list()}) :: {:ok, term()} | {:error, term()}
  def init({__MODULE__, opts}) when is_list(opts) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)

    case Server.start_link(opts) do
      {:ok, _pid} ->
        {:ok, configure(opts)}

      err when is_atom(err) ->
        {:error, err}

      error ->
        error
    end
  end

  @impl :gen_event
  def handle_call({:configure, opts}, _state) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)
    {:ok, :ok, configure(opts)}
  end

  @impl :gen_event
  def handle_event({level, _group_leader, message}, state) do
    # Messages eventually are flattened. Flattening them immediately saves time
    # later and appears to measurably reduce memory usage and reduction count
    # in RingLogger.Server in production devices.
    Server.log(level, flatten(message))
    {:ok, state}
  end

  def handle_event(:flush, state) do
    # No flushing needed for RingLogger
    {:ok, state}
  end

  @impl :gen_event
  def handle_info(_, state) do
    # Ignore everything else since it's hard to justify RingLogger crashing
    # on a bad message.
    {:ok, state}
  end

  @impl :gen_event
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @impl :gen_event
  def terminate(_reason, _state) do
    Server.stop()
    :ok
  end

  defp flatten({mod, msg, ts, md}) do
    {mod, IO.chardata_to_string(msg), ts, md}
  end
end
