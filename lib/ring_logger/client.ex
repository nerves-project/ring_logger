defmodule RingLogger.Client do
  @moduledoc """
  Interact with the RingLogger
  """
  use GenServer

  alias RingLogger.Server

  require Logger

  defstruct io: :stdio,
            colors: %{
              debug: :cyan,
              info: :normal,
              warn: :yellow,
              error: :red,
              enabled: IO.ANSI.enabled?()
            },
            metadata: [],
            format: Logger.Formatter.compile(nil),
            level: :debug,
            index: 0,
            module_levels: %{}

  @doc """
  Start up a client GenServer. Except for just getting the contents of the ring buffer, you'll
  need to create one of these. See `configure/2` for information on options.
  """
  @spec start_link(RingLogger.client_options()) :: GenServer.on_start()
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Stop a client.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(client_pid) do
    GenServer.stop(client_pid)
  end

  @doc """
  Fetch the current client configuration.
  """
  @spec config(pid()) :: RingLogger.client_options()
  def config(client_pid) do
    GenServer.call(client_pid, :config)
  end

  @doc """
  Update the client configuration.

  Options include:
  * `:io` - Defaults to `:stdio`
  * `:colors` -
  * `:metadata` - A KV list of additional metadata
  * `:format` - A custom format string, or a {module, function} tuple (see
    https://hexdocs.pm/logger/master/Logger.html#module-custom-formatting)
  * `:level` - The minimum log level to report.
  * `:module_levels` - a map of log level overrides per module. For example,
    %{MyModule => :error, MyOtherModule => :none}
  * `:application_levels` - a map of log level overrides per application. For example,
    %{:my_app => :error, :my_other_app => :none}. Note log levels set in `:module_levels`
    will take precedence.
  """
  @spec configure(GenServer.server(), RingLogger.client_options()) :: :ok
  def configure(client_pid, config) when is_list(config) do
    GenServer.call(client_pid, {:configure, config})
  end

  @doc """
  Attach the current IEx session to the logger. It will start printing log messages.
  """
  @spec attach(GenServer.server()) :: :ok
  def attach(client_pid) do
    GenServer.call(client_pid, :attach)
  end

  @doc """
  Detach the current IEx session from the logger.
  """
  @spec detach(GenServer.server()) :: :ok
  def detach(client_pid) do
    GenServer.call(client_pid, :detach)
  end

  @doc """
  Get the last n messages.

  Supported options:

  * `:pager` - an optional 2-arity function that takes an IO device and what to print
  """
  @spec tail(GenServer.server(), non_neg_integer(), RingLogger.client_options()) ::
          :ok | {:error, term()}
  def tail(client_pid, n, opts \\ []) do
    {io, to_print} = GenServer.call(client_pid, {:tail, n})

    pager = Keyword.get(opts, :pager, &IO.binwrite/2)
    pager.(io, to_print)
  end

  @doc """
  Get the next set of the messages in the log.

  Supported options:

  * `:pager` - an optional 2-arity function that takes an IO device and what to print
  """
  @spec next(GenServer.server(), RingLogger.client_options()) :: :ok | {:error, term()}
  def next(client_pid, opts \\ []) do
    {io, to_print} = GenServer.call(client_pid, :next)

    pager = Keyword.get(opts, :pager, &IO.binwrite/2)

    pager.(io, to_print)
  end

  @doc """
  Count the next set of the messages in the log.
  """
  @spec count_next(GenServer.server()) :: non_neg_integer()
  def count_next(client_pid) do
    GenServer.call(client_pid, :count_next)
  end

  @doc """
  Reset the index into the log for `tail/1` to the oldest entry.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(client_pid) do
    GenServer.call(client_pid, :reset)
  end

  @doc """
  Helper method for formatting log messages per the current client's
  configuration.
  """
  @spec format(GenServer.server(), RingLogger.entry()) :: :ok
  def format(client_pid, message) do
    GenServer.call(client_pid, {:format, message})
  end

  @doc """
  Format and save all log messages to the specified path.
  """
  @spec save(GenServer.server(), Path.t()) :: :ok | {:error, term()}
  def save(client_pid, path) do
    GenServer.call(client_pid, {:save, path})
  end

  @spec grep_metadata(
          GenServer.server(),
          atom(),
          String.t() | Regex.t(),
          RingLogger.client_options()
        ) ::
          :ok | {:error, term()}
  def grep_metadata(client_pid, key, match_value, opts)

  def grep_metadata(client_pid, key, match_value, opts) when is_binary(match_value) do
    with {:ok, regex} <- Regex.compile(match_value) do
      grep_metadata(client_pid, key, regex, opts)
    end
  end

  def grep_metadata(client_pid, key, %Regex{} = regex, opts) do
    {io, to_print} = GenServer.call(client_pid, {:grep_metadata, key, regex, opts})

    pager = Keyword.get(opts, :pager, &IO.binwrite/2)
    pager.(io, to_print)
  end

  @doc """
  Run a regular expression on each entry in the log and print out the matchers.

  Supported options:

  * `:pager` - an optional 2-arity function that takes an IO device and what to print
  * `:before` - Number of lines before the match to include
  * `:after` - NUmber of lines after the match to include
  """
  @spec grep(GenServer.server(), String.t() | Regex.t(), RingLogger.client_options()) ::
          :ok | {:error, term()}
  def grep(client_pid, regex_or_string, opts \\ [])

  def grep(client_pid, regex_string, opts) when is_binary(regex_string) do
    with {:ok, regex} <- Regex.compile(regex_string) do
      grep(client_pid, regex, opts)
    end
  end

  def grep(client_pid, %Regex{} = regex, opts) do
    {io, to_print} = GenServer.call(client_pid, {:grep, regex, opts})

    pager = Keyword.get(opts, :pager, &IO.binwrite/2)
    pager.(io, to_print)
  end

  def grep(_client_pid, _regex, _opts) do
    {:error, :invalid_regex}
  end

  @impl GenServer
  def init(config) do
    {:ok, configure_state(config)}
  end

  @impl GenServer
  def handle_info({:log, msg}, state) do
    _ = maybe_print(msg, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:config, _from, state) do
    config =
      Map.from_struct(state)
      |> Map.delete(:index)
      |> Map.to_list()

    {:reply, config, state}
  end

  def handle_call({:configure, config}, _from, state) do
    {:reply, :ok, configure_state(config, state)}
  end

  def handle_call(:attach, _from, state) do
    {:reply, Server.attach_client(self()), state}
  end

  def handle_call(:detach, _from, state) do
    {:reply, Server.detach_client(self()), state}
  end

  def handle_call(:next, _from, state) do
    case Server.get(state.index, 0) do
      [] ->
        # No messages
        {:reply, {state.io, "No new messages.\n"}, state}

      messages ->
        to_return =
          messages
          |> Enum.filter(&should_print?(&1, state))
          |> Enum.map(&format_message(&1, state))

        last_message = List.last(messages)
        next_index = message_index(last_message) + 1

        rc = [to_return, summary(messages, to_return)]

        {:reply, {state.io, rc}, %{state | index: next_index}}
    end
  end

  def handle_call(:count_next, _from, state) do
    count =
      Server.get(state.index, 0)
      |> Enum.count(&should_print?(&1, state))

    {:reply, count, state}
  end

  def handle_call({:tail, n}, _from, state) do
    to_return =
      Server.tail(n)
      |> Enum.filter(fn message -> should_print?(message, state) end)
      |> Enum.map(fn message -> format_message(message, state) end)

    {:reply, {state.io, to_return}, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | index: 0}}
  end

  def handle_call({:grep_metadata, key, match_value, _opts}, _from, state) do
    to_return =
      for message <- Server.get(0, 0),
          should_print?(message, state),
          has_metadata?(message, key, match_value),
          formatted = format_message(message, state),
          do: IO.chardata_to_string(formatted)

    {:reply, {state.io, to_return}, state}
  end

  def handle_call({:grep, regex, opts}, _from, state) do
    formatted_buff =
      for {message, i} <- Enum.with_index(Server.get(0, 0)),
          should_print?(message, state),
          formatted = format_message(message, state),
          bin = IO.chardata_to_string(formatted),
          do: {bin, Regex.match?(regex, bin), i}

    extras = determine_extra_grep_lines(formatted_buff, opts)

    to_return =
      for {bin, matched?, i} <- formatted_buff, matched? or i in extras do
        if matched?, do: maybe_color_grep(bin, regex, state), else: bin
      end

    {:reply, {state.io, to_return}, state}
  end

  def handle_call({:format, msg}, _from, state) do
    item = format_message(msg, state)
    {:reply, item, state}
  end

  def handle_call({:save, path}, _from, state) do
    rc =
      try do
        Server.get(0, 0)
        |> Stream.map(&format_message(&1, state))
        |> Stream.into(File.stream!(path))
        |> Stream.run()
      rescue
        error in File.Error ->
          {:error, error.reason}
      end

    {:reply, rc, state}
  end

  defp message_index(%{metadata: metadata}), do: Keyword.get(metadata, :index)

  defp format_message(
         %{level: level, message: message, timestamp: timestamp, metadata: metadata},
         state
       ) do
    metadata = take_metadata(metadata, state.metadata)

    state.format
    |> apply_format(level, message, timestamp, metadata)
    |> color_event(level, state.colors, metadata)
  end

  ## Helpers

  defp apply_format({mod, fun}, level, msg, ts, metadata) do
    apply(mod, fun, [level, msg, ts, metadata])
  end

  defp apply_format(format, level, msg, ts, metadata) do
    Logger.Formatter.format(format, level, msg, ts, metadata)
  end

  defp configure_state(config, state \\ %__MODULE__{}) do
    defaults = build_defaults()

    config =
      Keyword.merge(defaults, config)
      |> Keyword.drop([:index])
      |> Enum.map(&configure_option(&1))

    config = Keyword.put(config, :module_levels, configure_module_levels(config))

    struct(state, config)
  end

  defp build_defaults() do
    deprecated_defaults = Application.get_all_env(:ring_logger)

    defaults =
      Application.get_env(:logger, RingLogger, [])
      |> Keyword.put_new(:colors, [])

    merge_deprecated_defaults(deprecated_defaults, defaults)
  end

  defp merge_deprecated_defaults([], defaults), do: defaults

  defp merge_deprecated_defaults(deprecated_defaults, defaults) do
    message = """
    Setting RingLogger configuration under `:ring_logger` is deprecated. Instead configuration should be set under :logger, RingLogger

    In your config.exs or other configuration file change:

        config :ring_logger,
          <configurations>

    To:

        config :logger, RingLogger,
          <configurations>
    """

    IO.warn(message)

    Keyword.merge(deprecated_defaults, defaults)
  end

  defp configure_option({:colors, colors}) do
    {:colors, configure_colors(colors)}
  end

  defp configure_option({:metadata, metadata}) do
    {:metadata, configure_metadata(metadata)}
  end

  defp configure_option({:format, format}) do
    {:format, configure_formatter(format)}
  end

  defp configure_option(opt), do: opt

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp configure_colors(colors) when is_list(colors) do
    %{
      debug: Keyword.get(colors, :debug, :cyan),
      info: Keyword.get(colors, :info, :normal),
      warn: Keyword.get(colors, :warn, :yellow),
      error: Keyword.get(colors, :error, :red),
      enabled: Keyword.get(colors, :enabled, IO.ANSI.enabled?())
    }
  end

  defp configure_colors(colors) when is_map(colors) do
    configure_colors(Map.to_list(colors))
  end

  defp configure_colors(colors) do
    _ =
      Logger.warning("""
      unknown RingLogger.Client colors option:

        #{inspect(colors)}

      Using defaults...
      """)

    configure_colors([])
  end

  defp meet_level?(_lvl, nil), do: true
  defp meet_level?(_lvl, :none), do: false
  defp meet_level?(:warn, min), do: Logger.compare_levels(:warning, min) != :lt
  defp meet_level?(lvl, min), do: Logger.compare_levels(lvl, min) != :lt

  defp take_metadata(metadata, :all), do: metadata

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
  end

  defp color_event(data, _level, %{enabled: false}, _md), do: data

  defp color_event(data, level, %{enabled: true} = colors, md) do
    color = md[:ansi_color] || Map.fetch!(colors, level)
    [IO.ANSI.format_fragment(color, true), data, IO.ANSI.reset()]
  end

  defp configure_formatter({mod, fun}), do: {mod, fun}

  defp configure_formatter(format) do
    Logger.Formatter.compile(format)
  end

  @spec configure_module_levels(RingLogger.client_options()) :: map()
  def configure_module_levels(config) do
    module_levels = Keyword.get(config, :module_levels, %{})

    Keyword.get(config, :application_levels, %{})
    |> Enum.reduce(module_levels, &add_module_levels_for_application/2)
  end

  defp add_module_levels_for_application({app, level}, module_levels) do
    modules_for_application(app)
    |> Enum.reduce(module_levels, &Map.put_new(&2, &1, level))
  end

  defp modules_for_application(app), do: Application.spec(app, :modules) || []

  defp maybe_print(msg, state) do
    if should_print?(msg, state) do
      item = format_message(msg, state)
      IO.binwrite(state.io, item)
    end
  end

  defp get_module_from_msg(%{metadata: metadata}) do
    Keyword.get(metadata, :module)
  end

  defp should_print?(%{level: level} = msg, %__MODULE__{module_levels: module_levels} = state) do
    module = get_module_from_msg(msg)

    with module_level when not is_nil(module_level) <- Map.get(module_levels, module),
         true <- meet_level?(level, module_level) do
      true
    else
      nil ->
        meet_level?(level, state.level)

      _ ->
        false
    end
  end

  defp summary(messages, []) do
    "All #{Enum.count(messages)} new messages filtered out.\n"
  end

  defp summary(messages, to_return) do
    "\n#{Enum.count(to_return)} out of #{Enum.count(messages)} new messages shown.\n"
  end

  defp maybe_color_grep(bin, regex, %{colors: %{enabled: true}}) do
    Regex.replace(regex, bin, &IO.ANSI.format_fragment([:inverse, &1, :inverse_off], true))
  end

  defp maybe_color_grep(bin, _regex, _state), do: bin

  defp determine_extra_grep_lines(buff, opts) do
    if Keyword.has_key?(opts, :before) or Keyword.has_key?(opts, :after) do
      before = opts[:before] || 0
      aft = opts[:after] || 0

      for({_, true, i} <- buff, do: Enum.to_list((i - before)..(i + aft)))
      |> List.flatten()
      |> Enum.uniq()
    else
      []
    end
  end

  @spec has_metadata?(RingLogger.entry(), atom(), String.t() | Regex.t()) :: boolean()
  defp has_metadata?(%{metadata: metadata}, key, match_value) do
    case metadata[key] do
      nil -> false
      val when is_binary(val) -> val =~ match_value
      val when val == match_value -> true
      _ -> false
    end
  end
end
