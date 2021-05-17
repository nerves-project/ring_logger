defmodule RingLogger.Client do
  use GenServer
  require Logger

  @moduledoc """
  Interact with the RingLogger
  """

  alias RingLogger.Server

  defmodule State do
    @moduledoc false
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
  end

  @doc """
  Start up a client GenServer. Except for just getting the contents of the ring buffer, you'll
  need to create one of these. See `configure/2` for information on options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
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
  @spec config(pid()) :: [RingLogger.client_option()]
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
  @spec configure(GenServer.server(), [RingLogger.client_option()]) :: :ok
  def configure(client_pid, config) do
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
  @spec tail(GenServer.server(), non_neg_integer()) :: :ok | {:error, term()}
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
  @spec next(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def next(client_pid, opts \\ []) do
    {io, to_print} = GenServer.call(client_pid, :next)

    pager = Keyword.get(opts, :pager, &IO.binwrite/2)
    pager.(io, to_print)
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

  @doc """
  Run a regular expression on each entry in the log and print out the matchers.

  Supported options:

  * `:pager` - an optional 2-arity function that takes an IO device and what to print
  """
  @spec grep(GenServer.server(), String.t() | Regex.t(), [RingLogger.client_option()]) ::
          :ok | {:error, term()}
  def grep(client_pid, regex_or_string, opts \\ [])

  def grep(client_pid, regex_string, opts) when is_binary(regex_string) do
    with {:ok, regex} <- Regex.compile(regex_string) do
      grep(client_pid, regex, opts)
    end
  end

  def grep(client_pid, %Regex{} = regex, opts) do
    {io, to_print} = GenServer.call(client_pid, {:grep, regex})

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

  def handle_call({:grep, regex}, _from, state) do
    to_return =
      Server.get(0, 0)
      |> Enum.filter(fn message -> should_print?(message, state) end)
      |> Enum.map(fn message -> format_message(message, state) end)
      |> Enum.map(&IO.iodata_to_binary/1)
      |> Enum.filter(&Regex.match?(regex, &1))

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

  defp message_index({_level, {_, _msg, _ts, md}}), do: Keyword.get(md, :index)

  defp format_message({level, {_, msg, ts, md}}, state) do
    metadata = take_metadata(md, state.metadata)

    state.format
    |> apply_format(level, msg, ts, metadata)
    |> color_event(level, state.colors, md)
  end

  ## Helpers

  defp apply_format({mod, fun}, level, msg, ts, metadata) do
    apply(mod, fun, [level, msg, ts, metadata])
  end

  defp apply_format(format, level, msg, ts, metadata) do
    Logger.Formatter.format(format, level, msg, ts, metadata)
  end

  defp configure_state(config, state \\ %State{}) do
    defaults = Application.get_all_env(:ring_logger)

    config =
      Keyword.merge(defaults, config)
      |> Keyword.drop([:index])
      |> Enum.map(&configure_option(&1))

    config = Keyword.put(config, :module_levels, configure_module_levels(config))

    struct(state, config)
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
      Logger.warn("""
      unknown RingLogger.Client colors option:

        #{inspect(colors)}

      Using defaults...
      """)

    configure_colors([])
  end

  defp meet_level?(_lvl, nil), do: true
  defp meet_level?(_lvl, :none), do: false

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

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

  defp get_module_from_msg({_, {_, _, _, meta}}) do
    Keyword.get(meta, :module)
  end

  defp should_print?({level, _} = msg, %State{module_levels: module_levels} = state) do
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
end
