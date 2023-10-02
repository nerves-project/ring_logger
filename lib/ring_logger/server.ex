defmodule RingLogger.Server do
  @moduledoc false
  use GenServer

  # This GenServer is separate from the Logger backend to allow for
  # `RingLogger.Client`s to query the circular buffers without halting
  # the backend at all. The Logger backend `cast`s all data over to
  # this process.

  alias RingLogger.Buffer
  alias RingLogger.Client
  alias RingLogger.Persistence

  require Logger

  @default_max_size 1024
  @default_persist_seconds 300

  defstruct clients: [],
            buffers: %{},
            default_buffer: nil,
            index: 0,
            persist_path: nil,
            persist_seconds: 300

  @spec start_link([RingLogger.server_option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec stop() :: :ok
  def stop() do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Fetch the current configuration for the server and any attached clients.
  """
  @spec config() :: [RingLogger.server_option()]
  def config() do
    GenServer.call(__MODULE__, :config)
  end

  @spec configure([RingLogger.server_option()]) :: :ok
  def configure(opts) do
    GenServer.call(__MODULE__, {:configure, opts})
  end

  @spec attach_client(pid()) :: :ok
  def attach_client(client_pid) do
    GenServer.call(__MODULE__, {:attach, client_pid})
  end

  @spec detach_client(pid()) :: :ok
  def detach_client(client_pid) do
    GenServer.call(__MODULE__, {:detach, client_pid})
  end

  @spec get(non_neg_integer(), non_neg_integer()) :: [RingLogger.entry()]
  def get(start_index, n) do
    GenServer.call(__MODULE__, {:get, start_index, n})
  end

  @type time() :: {{1970..10000, 1..12, 1..31}, {0..23, 0..59, 0..59, 0..999}}
  @spec log(
          Logger.level(),
          {Logger, Logger.message(), time(), Logger.metadata()}
        ) :: :ok
  def log(level, message) do
    GenServer.cast(__MODULE__, {:log, level, message})
  end

  @spec tail(non_neg_integer()) :: [RingLogger.entry()]
  def tail(n) do
    GenServer.call(__MODULE__, {:tail, n})
  end

  @spec clear() :: :ok
  def clear() do
    GenServer.call(__MODULE__, :clear)
  end

  @impl GenServer
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)

    buffers = reset_buffers(Keyword.get(opts, :buffers, %{}))

    state = %__MODULE__{
      buffers: buffers,
      default_buffer: CircularBuffer.new(max_size),
      persist_path: Keyword.get(opts, :persist_path),
      persist_seconds: Keyword.get(opts, :persist_seconds, @default_persist_seconds)
    }

    {:ok, state, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    case !is_nil(state.persist_path) do
      true ->
        Process.send_after(self(), :tick, state.persist_seconds * 1000)
        {:noreply, load_persist_path(state)}

      false ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:clear, _from, state) do
    max_size = state.default_buffer.max_size

    buffers =
      Enum.map(state.buffers, fn buffer ->
        %{buffer | circular_buffer: CircularBuffer.new(buffer.max_size)}
      end)

    {:reply, :ok, %{state | buffers: buffers, default_buffer: CircularBuffer.new(max_size)}}
  end

  def handle_call(:config, _from, state) do
    buffers =
      state.buffers
      |> Enum.map(fn buffer ->
        {buffer.name, Map.take(buffer, [:levels, :max_size])}
      end)
      |> Enum.into(%{})

    config = %{
      max_size: state.default_buffer.max_size,
      buffers: buffers
    }

    {:reply, config, state}
  end

  def handle_call({:configure, opts}, _from, state) do
    logs = merge_buffers(state)

    max_size = Keyword.get(opts, :max_size, @default_max_size)

    state = %__MODULE__{state | default_buffer: CircularBuffer.new(max_size)}

    state =
      case Keyword.get(opts, :buffers) do
        nil ->
          state

        buffers ->
          %__MODULE__{state | buffers: reset_buffers(buffers)}
      end

    # Reinsert old buffers to let new max size filter out
    state = Enum.reduce(logs, state, &insert_log(&2, &1))

    {:reply, :ok, state}
  end

  def handle_call({:attach, client_pid}, _from, state) do
    {:reply, :ok, attach_client(client_pid, state)}
  end

  def handle_call({:detach, pid}, _from, state) do
    {:reply, :ok, detach_client(pid, state)}
  end

  def handle_call({:get, start_index, 0}, _from, state) do
    logs = merge_buffers(state)

    first_index = state.index - Enum.count(logs)
    adjusted_start_index = max(start_index - first_index, 0)
    items = Enum.drop(logs, adjusted_start_index)

    {:reply, items, state}
  end

  def handle_call({:get, start_index, n}, _from, state) do
    logs = merge_buffers(state)

    first_index = state.index - Enum.count(logs)
    last_index = state.index

    {adjusted_start_index, adjusted_n} =
      {start_index, n}
      |> adjust_left(first_index)
      |> adjust_right(last_index)

    items = Enum.slice(logs, adjusted_start_index, adjusted_n)

    {:reply, items, state}
  end

  def handle_call({:tail, n}, _from, state) do
    logs = merge_buffers(state)

    {:reply, Enum.take(logs, -n), state}
  end

  @impl GenServer
  def handle_cast({:log, level, message}, state) do
    {:noreply, push(level, message, state)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, _, pid, _reason}, state) do
    {:noreply, detach_client(pid, state)}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.persist_seconds * 1000)

    case Persistence.save(state.persist_path, merge_buffers(state)) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("RingLogger ran into an issue persisting the log: #{reason}")

        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.clients, fn {client_pid, _ref} -> Client.stop(client_pid) end)
    :ok
  end

  defp adjust_left({offset, n}, i) when i > offset do
    {i, max(0, n - (i - offset))}
  end

  defp adjust_left(loc, _i), do: loc

  defp adjust_right({offset, n}, i) when i < offset + n do
    {offset, i - offset}
  end

  defp adjust_right(loc, _i), do: loc

  defp attach_client(client_pid, state) do
    if client_info(client_pid, state) == nil do
      ref = Process.monitor(client_pid)
      %{state | clients: [{client_pid, ref} | state.clients]}
    else
      state
    end
  end

  defp detach_client(client_pid, state) do
    case client_info(client_pid, state) do
      {_client_pid, ref} ->
        Process.demonitor(ref)

        remaining_clients = List.keydelete(state.clients, client_pid, 0)
        %{state | clients: remaining_clients}

      nil ->
        state
    end
  end

  defp client_info(client_pid, state) do
    List.keyfind(state.clients, client_pid, 0)
  end

  defp push(level, {module, message, timestamp, metadata}, state) do
    index = state.index

    log_entry = %{
      level: level,
      module: module,
      message: message,
      timestamp: timestamp,
      metadata: Keyword.put(metadata, :index, index)
    }

    Enum.each(state.clients, &send_log(&1, log_entry))

    state = insert_log(state, log_entry)

    %{state | index: index + 1}
  end

  defp insert_log(state, log_entry) do
    case Enum.find(state.buffers, &(log_entry.level in &1.levels)) do
      nil ->
        default_buffer = CircularBuffer.insert(state.default_buffer, log_entry)
        %{state | default_buffer: default_buffer}

      buffer ->
        buffers = List.delete(state.buffers, buffer)
        circular_buffer = CircularBuffer.insert(buffer.circular_buffer, log_entry)
        buffer = %{buffer | circular_buffer: circular_buffer}
        %{state | buffers: [buffer | buffers]}
    end
  end

  defp send_log({client_pid, _ref}, log_entry) do
    send(client_pid, {:log, log_entry})
  end

  defp merge_buffers(state) do
    (Enum.map(state.buffers, & &1.circular_buffer) ++ [state.default_buffer])
    |> Enum.flat_map(& &1)
    |> Enum.sort_by(fn %{metadata: metadata} ->
      metadata[:index]
    end)
  end

  defp reset_buffers(buffers) do
    Enum.map(buffers, fn {name, config} ->
      %Buffer{
        name: name,
        levels: config[:levels],
        max_size: config[:max_size],
        circular_buffer: CircularBuffer.new(config[:max_size])
      }
    end)
  end

  defp load_persist_path(state) do
    case Persistence.load(state.persist_path) do
      logs when is_list(logs) ->
        state =
          logs
          |> Enum.with_index()
          |> Enum.reduce(state, fn {log_entry, index}, state ->
            log_entry = %{log_entry | metadata: Keyword.put(log_entry.metadata, :index, index)}
            insert_log(state, log_entry)
          end)

        %{state | index: Enum.count(logs)}

      {:error, :corrupted} ->
        timestamp = :os.system_time(:microsecond)
        micro = rem(timestamp, 1_000_000)

        {date, {hours, minutes, seconds}} =
          :calendar.system_time_to_universal_time(timestamp, :microsecond)

        log_entry = %{
          level: :warn,
          module: Logger,
          message: "RingLogger could not load the persistence file, it is corrupt",
          timestamp: {date, {hours, minutes, seconds, div(micro, 1000)}},
          metadata: [index: 1]
        }

        state = insert_log(state, log_entry)

        %{state | index: 1}

      {:error, _reason} ->
        state
    end
  end
end
