defmodule RingLogger.Server do
  @moduledoc false
  use GenServer

  @default_max_size 1024

  defstruct clients: [],
            buffer: nil,
            index: 0

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec stop() :: :ok
  def stop() do
    GenServer.stop(__MODULE__)
  end

  @spec configure(keyword()) :: :ok
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

  @spec log(Logger.level(), String.t(), tuple(), keyword()) :: :ok
  def log(level, message, timestamp, metadata) do
    GenServer.cast(__MODULE__, {:log, level, message, timestamp, metadata})
  end

  @spec get(non_neg_integer(), non_neg_integer()) :: [RingLogger.entry()]
  def get(start_index \\ 0, n \\ 0) do
    GenServer.call(__MODULE__, {:get, start_index, n})
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

    state = %__MODULE__{
      buffer: CircularBuffer.new(max_size)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:clear, _from, state) do
    max_size = state.buffer.max_size
    {:reply, :ok, %{state | buffer: CircularBuffer.new(max_size), index: 0}}
  end

  def handle_call({:configure, opts}, _from, state) do
    max_size = Keyword.get(opts, :max_size, state.buffer.max_size)

    # Rebuild buffer with new size, reinserting existing entries
    if max_size != state.buffer.max_size do
      entries = Enum.to_list(state.buffer)
      new_buffer = CircularBuffer.new(max_size)

      new_buffer =
        Enum.reduce(entries, new_buffer, fn entry, buf ->
          CircularBuffer.insert(buf, entry)
        end)

      {:reply, :ok, %{state | buffer: new_buffer}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:attach, client_pid}, _from, state) do
    {:reply, :ok, do_attach_client(client_pid, state)}
  end

  def handle_call({:detach, pid}, _from, state) do
    {:reply, :ok, do_detach_client(pid, state)}
  end

  def handle_call({:get, start_index, 0}, _from, state) do
    entries = Enum.to_list(state.buffer)

    first_index = state.index - length(entries)
    adjusted_start_index = max(start_index - first_index, 0)
    items = Enum.drop(entries, adjusted_start_index)

    {:reply, items, state}
  end

  def handle_call({:get, start_index, n}, _from, state) do
    entries = Enum.to_list(state.buffer)

    first_index = state.index - length(entries)
    last_index = state.index

    {adjusted_start_index, adjusted_n} =
      {start_index, n}
      |> adjust_left(first_index)
      |> adjust_right(last_index)

    items = Enum.slice(entries, adjusted_start_index, adjusted_n)

    {:reply, items, state}
  end

  def handle_call({:tail, n}, _from, state) do
    entries = Enum.to_list(state.buffer)
    {:reply, Enum.take(entries, -n), state}
  end

  @impl GenServer
  def handle_cast({:log, level, message, timestamp, metadata}, state) do
    {:noreply, push(level, message, timestamp, metadata, state)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, _, pid, _reason}, state) do
    {:noreply, do_detach_client(pid, state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    close_all_clients(state)
    :ok
  end

  defp close_all_clients(state) do
    Enum.each(state.clients, fn {client_pid, _ref} ->
      RingLogger.Client.stop(client_pid)
    end)
  end

  defp push(level, message, timestamp, metadata, state) do
    index = state.index

    log_entry = %{
      level: level,
      module: metadata[:module] || Logger,
      message: message,
      timestamp: timestamp,
      metadata: Keyword.put(metadata, :index, index)
    }

    Enum.each(state.clients, &send_log(&1, log_entry))

    buffer = CircularBuffer.insert(state.buffer, log_entry)
    %{state | buffer: buffer, index: index + 1}
  end

  defp send_log({client_pid, _ref}, log_entry) do
    send(client_pid, {:log, log_entry})
  end

  defp do_attach_client(client_pid, state) do
    if client_info(client_pid, state) == nil do
      ref = Process.monitor(client_pid)
      %{state | clients: [{client_pid, ref} | state.clients]}
    else
      state
    end
  end

  defp do_detach_client(client_pid, state) do
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

  defp adjust_left({offset, n}, i) when i > offset do
    {i, max(0, n - (i - offset))}
  end

  defp adjust_left(loc, _i), do: loc

  defp adjust_right({offset, n}, i) when i < offset + n do
    {offset, i - offset}
  end

  defp adjust_right(loc, _i), do: loc
end
