defmodule RingLogger do
  @moduledoc """
  This is an in-memory ring buffer handler for the Erlang `:logger`.

  Install it by adding it to your `config.exs`:

  ```elixir
  import Config

  # Add the RingLogger handler
  config :logger, :handlers,
    ring_logger: %{module: RingLogger.Handler, config: %{max_size: 1024}}
  ```

  Or add manually at runtime:

  ```elixir
  RingLogger.add(max_size: 1024)
  ```

  Once added as a handler, you have two options depending on whether you're
  accessing the `RingLogger` via the IEx prompt or via code. If you're at the
  IEx prompt, use the helper methods in here like `attach`, `detach`, `next`,
  `tail`, `grep`, etc. They'll automate a few things behind the scenes. If
  you're writing a program that needs to get log messages, use `get` or
  `start_link` a `RingLogger.Client` and call its methods directly.
  """

  alias RingLogger.Autoclient
  alias RingLogger.Server

  @typedoc "Option values used by the ring logger handler"
  @type handler_option() :: {:max_size, pos_integer()}

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
          message: String.t(),
          timestamp: {{1970..10000, 1..12, 1..31}, {0..23, 0..59, 0..59, 0..999}},
          metadata: keyword()
        }

  @typep custom_formatter() :: {module, function}

  @default_handler_id :ring_logger

  #
  # Handler management API
  #

  @doc """
  Add the RingLogger handler to the Erlang logger.

  Options include:

  * `:max_size` - the max number of log messages to store at a time (default: 1024)
  * `:id` - the handler id (default: `:ring_logger`)
  """
  @spec add(keyword()) :: :ok | {:error, term()}
  def add(opts \\ []) do
    id = Keyword.get(opts, :id, @default_handler_id)
    max_size = Keyword.get(opts, :max_size, 1024)

    config = %{
      config: %{max_size: max_size}
    }

    case :logger.add_handler(id, RingLogger.Handler, config) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Remove the RingLogger handler from the Erlang logger.
  """
  @spec remove(atom()) :: :ok | {:error, term()}
  def remove(id \\ @default_handler_id) do
    :logger.remove_handler(id)
  end

  #
  # IEx API
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
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.write/2`.
  """
  @spec next(client_options()) :: :ok | {:error, term()}
  defdelegate next(opts \\ []), to: Autoclient

  @doc """
  Count the next messages in the log

  NOTE: This function may change in future releases.

  Options include:

  * Options from `attach/1`
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.write/2`.
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
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.write/2`.
  """
  @spec tail(non_neg_integer(), client_options()) :: :ok
  def tail(n, opts), do: Autoclient.tail(n, opts)

  @doc """
  Starts the Ring Logger Viewer TUI app on the current prompt
  """
  @spec viewer() :: :ok
  def viewer(), do: RingLogger.Viewer.view()

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
  * `:pager` - a function for printing log messages to the console. Defaults to `IO.write/2`.
  * `:before` - Number of lines before the match to include
  * `:after` - Number of lines after the match to include
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
  @spec configure([handler_option]) :: :ok
  defdelegate configure(opts), to: Server
end
