defmodule LoggerCircularBuffer.Client do
  use GenServer

  alias LoggerCircularBuffer.Server

  defstruct io: nil,
            colors: nil,
            metadata: nil,
            format: nil,
            level: nil

  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config)
  end

  def stop(client_pid) do
    GenServer.stop(client_pid)
  end

  @doc """
  """

  @spec attach(Genserver.server()) :: :ok
  def attach(client_pid) do
    GenServer.call(client_pid, :attach)
  end

  @spec detach(Genserver.server()) :: :ok
  def detach(client_pid) do
    GenServer.call(client_pid, :detach)
  end

  def tail(client_pid) do
    GenServer.call(client_pid, :tail)
  end

  def reset(client_pid) do
    GenServer.call(client_pid, :reset)
  end

  def format(client_pid, message) do
    GenServer.call(client_pid, {:format, message})
  end

  def init(config) do
    state = %__MODULE__{
      io: Keyword.get(config, :io, :stdio),
      colors: configure_colors(config),
      metadata: Keyword.get(config, :metadata, []) |> configure_metadata(),
      format: Logger.Formatter.compile(Keyword.get(config, :format)),
      level: Keyword.get(config, :level)
    }

    :ok = Server.attach_client(self())

    {:ok, state}
  end

  def handle_info({:log, {level, _} = msg}, state) do
    if meet_level?(level, state.level) do
      item = format_message(msg, state)

      IO.binwrite(state.io, item)
    end

    {:noreply, state}
  end

  def handle_call(:attach, _from, state) do
    Server.attach_client(self())
    {:reply, :ok, state}
  end

  def handle_call(:detach, _from, state) do
    Server.detach_client(self())
    {:reply, :ok, state}
  end

  def handle_call(:tail, _from, state) do
    {:reply, [], state}
  end

  def handle_call({:format, msg}, _from, state) do
    item = format_message(msg, state)
    {:reply, item, state}
  end

  defp format_message({level, {_, msg, ts, md}}, state) do
    metadata = take_metadata(md, state.metadata)

    state.format
    |> Logger.Formatter.format(level, msg, ts, metadata)
    |> color_event(level, state.colors, md)
  end

  ## Helpers
  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp configure_colors(config) do
    colors = Keyword.get(config, :colors, [])

    %{
      debug: Keyword.get(colors, :debug, :cyan),
      info: Keyword.get(colors, :info, :normal),
      warn: Keyword.get(colors, :warn, :yellow),
      error: Keyword.get(colors, :error, :red),
      enabled: Keyword.get(colors, :enabled, IO.ANSI.enabled?())
    }
  end

  defp meet_level?(_lvl, nil), do: true
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
    [IO.ANSI.format_fragment(color, true), data | IO.ANSI.reset()]
  end
end
