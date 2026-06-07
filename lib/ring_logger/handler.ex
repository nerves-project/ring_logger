defmodule RingLogger.Handler do
  @moduledoc """
  An Erlang `:logger` handler that stores log messages in an in-memory ring buffer.

  This handler is the core of RingLogger. It receives log events from the Erlang
  logger and forwards them to the `RingLogger.Server` GenServer for storage and
  client notification.

  ## Adding the handler

      :logger.add_handler(:ring_logger, RingLogger.Handler, %{
        config: %{max_size: 1024}
      })

  ## Configuration

    * `:max_size` - the maximum number of log entries to store (default: 1024)
  """

  @default_max_size 1024

  @doc false
  @spec adding_handler(:logger.handler_config()) ::
          {:ok, :logger.handler_config()} | {:error, term()}
  def adding_handler(config) do
    ring_config = config[:config] || %{}
    max_size = Map.get(ring_config, :max_size, @default_max_size)

    case RingLogger.Server.start_link(max_size: max_size) do
      {:ok, _pid} ->
        {:ok, config}

      {:error, {:already_started, _pid}} ->
        # Server already running, just update config
        RingLogger.Server.configure(max_size: max_size)
        {:ok, config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec removing_handler(:logger.handler_config()) :: :ok
  def removing_handler(_config) do
    RingLogger.Server.stop()
    :ok
  end

  @doc false
  @spec changing_config(:set | :update, :logger.handler_config(), :logger.handler_config()) ::
          {:ok, :logger.handler_config()}
  def changing_config(:set, _old_config, new_config) do
    ring_config = new_config[:config] || %{}
    max_size = Map.get(ring_config, :max_size, @default_max_size)
    RingLogger.Server.configure(max_size: max_size)
    {:ok, new_config}
  end

  def changing_config(:update, old_config, new_config) do
    merged = Map.merge(old_config, new_config)
    changing_config(:set, old_config, merged)
  end

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: :ok
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_msg(msg)
    message = safe_chardata_to_string(message)

    timestamp = meta_to_timestamp(meta)
    metadata = meta_to_metadata(meta)

    RingLogger.Server.log(level, message, timestamp, metadata)
    :ok
  end

  @doc false
  @spec filter_config(:logger.handler_config()) :: :logger.handler_config()
  def filter_config(config) do
    Map.drop(config, [:config])
  end

  # Convert Erlang logger message formats to a string
  defp format_msg({:string, msg}), do: msg
  defp format_msg({:report, report}) when is_map(report), do: inspect(report)
  defp format_msg({:report, report}) when is_list(report), do: inspect(report)
  defp format_msg({format, args}), do: :io_lib.format(format, args) |> IO.chardata_to_string()

  # Convert :logger meta.time (microseconds since epoch) to the Logger timestamp format
  # {{year, month, day}, {hour, min, sec, ms}}
  defp meta_to_timestamp(%{time: time}) do
    microseconds = time
    milliseconds = div(rem(microseconds, 1_000_000), 1000)
    seconds = div(microseconds, 1_000_000)

    {date, {h, m, s}} = :calendar.system_time_to_universal_time(seconds, :second)
    {date, {h, m, s, milliseconds}}
  end

  defp meta_to_timestamp(_meta) do
    # Fallback if no time in metadata
    {{0, 0, 0}, {0, 0, 0, 0}}
  end

  # Convert Erlang logger meta map to Elixir Logger metadata keyword list
  defp meta_to_metadata(meta) do
    metadata =
      meta
      |> Map.drop([:time, :gl])
      |> Map.to_list()

    # Extract :module from :mfa if not already present
    case {Keyword.get(metadata, :module), Keyword.get(metadata, :mfa)} do
      {nil, {module, _fun, _arity}} ->
        [{:module, module} | metadata]

      _ ->
        metadata
    end
  end

  defp safe_chardata_to_string(msg) when is_binary(msg) do
    if String.valid?(msg, :fast_ascii) do
      msg
    else
      String.replace_invalid(msg)
    end
  end

  defp safe_chardata_to_string(msg) when is_list(msg) do
    IO.chardata_to_string(msg)
  rescue
    UnicodeConversionError ->
      safe_iodata_to_binary(msg)
  end

  defp safe_chardata_to_string(msg), do: to_string(msg)

  defp safe_iodata_to_binary(msg) do
    IO.iodata_to_binary(msg) |> String.replace_invalid()
  rescue
    ArgumentError ->
      inspect(msg)
  end
end
