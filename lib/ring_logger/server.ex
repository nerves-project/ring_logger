defmodule RingLogger.Server do
  use GenServer

  @moduledoc false
  @default_max_size 1024

  alias RingLogger.Client

  defmodule State do
    @moduledoc false

    defstruct clients: [],
              cb: nil,
              index: 0
  end

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

  @spec log(
          Logger.level(),
          {Logger, Logger.message(), Logger.Formatter.time(), Logger.metadata()}
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

    {:ok, %State{cb: CircularBuffer.new(max_size)}}
  end

  @impl GenServer
  def handle_call(:clear, _from, state) do
    max_size = state.cb.max_size

    {:reply, :ok, %{state | cb: CircularBuffer.new(max_size)}}
  end

  def handle_call(:config, _from, state) do
    config = %{max_size: state.cb.max_size}

    {:reply, config, state}
  end

  def handle_call({:configure, opts}, _from, state) do
    case Keyword.get(opts, :max_size) do
      nil ->
        {:reply, :ok, state}

      max_size ->
        {:reply, :ok, %State{state | cb: CircularBuffer.new(max_size)}}
    end
  end

  def handle_call({:attach, client_pid}, _from, state) do
    {:reply, :ok, attach_client(client_pid, state)}
  end

  def handle_call({:detach, pid}, _from, state) do
    {:reply, :ok, detach_client(pid, state)}
  end

  def handle_call({:get, start_index, 0}, _from, state) do
    first_index = state.index - Enum.count(state.cb)
    adjusted_start_index = max(start_index - first_index, 0)
    items = Enum.drop(state.cb, adjusted_start_index)

    {:reply, items, state}
  end

  def handle_call({:get, start_index, n}, _from, state) do
    first_index = state.index - Enum.count(state.cb)
    last_index = state.index

    {adjusted_start_index, adjusted_n} =
      {start_index, n}
      |> adjust_left(first_index)
      |> adjust_right(last_index)

    items = Enum.slice(state.cb, adjusted_start_index, adjusted_n)

    {:reply, items, state}
  end

  def handle_call({:tail, n}, _from, state) do
    {:reply, Enum.take(state.cb, -n), state}
  end

  @impl GenServer
  def handle_cast({:log, level, message}, state) do
    {:noreply, push(level, message, state)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, _, pid, _reason}, state) do
    {:noreply, detach_client(pid, state)}
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
    if !client_info(client_pid, state) do
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

  defp push(level, {mod, msg, ts, md}, state) do
    index = state.index
    log_entry = {level, {mod, msg, ts, Keyword.put(md, :index, index)}}

    Enum.each(state.clients, &send_log(&1, log_entry))

    new_cb = CircularBuffer.insert(state.cb, log_entry)
    %{state | cb: new_cb, index: index + 1}
  end

  defp send_log({client_pid, _ref}, log_entry) do
    send(client_pid, {:log, log_entry})
  end
end
