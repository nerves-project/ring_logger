defmodule Logger.RemoteConsole.Server do
  use GenServer

  alias Logger.RemoteConsole.Client

  @buffer_size 100
  @opts [:buffer_size]

  defmodule State do
    defstruct [
      clients: [],
      buffer: [],
      buffer_actual_size: 0,
      buffer_size: nil
    ]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def configure(opts) do
    GenServer.call(__MODULE__, {:configure, opts})
  end

  def attach(config \\ []) do    
    {:ok, task} = Task.start_link(Client, :loop, [])
    GenServer.call(__MODULE__, {:attach, self(), task, config})
  end

  def detach() do
    GenServer.call(__MODULE__, {:detach, self()})
  end

  def get_buffer() do
    GenServer.call(__MODULE__, :get_buffer)
  end

  def flush_buffer() do
    GenServer.cast(__MODULE__, :flush)
  end

  def log(msg) do
    GenServer.cast(__MODULE__, {:log, msg})
  end

  def init(opts) do
    buffer_size = opts[:buffer_size] || @buffer_size

    {:ok, %State{
      clients: [],
      buffer: :queue.new(),
      buffer_size: buffer_size
    }}
  end

  def handle_call({:configure, opts}, _from, state) do
    opts = 
      opts
      |> Keyword.take(@opts)
      |> Enum.into(%{})
    state = 
      state
      |> Map.merge(opts)
      |> trim_buffer
    {:reply, opts, state}
  end

  def handle_call({:attach, pid, task, config}, _from, state) do
    client = Client.init(pid, task, config)
    {:reply, {:ok, client}, attach_client(client, state)}
  end

  def handle_call({:detach, pid}, _from, state) do
    {:reply, :ok, detach_client(pid, state)}
  end

  def handle_call(:get_buffer, _from, state) do
    {:reply, :queue.to_list(state.buffer), state}
  end

  def handle_cast({:log, msg}, state) do
    Enum.each(state.clients, &send(&1.task, {:log, msg, &1.config}))
    {:noreply, buffer_message(msg, state)}
  end

  def handle_cast(:flush, state) do
    {:noreply, %{state | buffer: :queue.new(), buffer_actual_size: 0}}
  end

  def handle_info({:DOWN, _ref, _, pid, _reason}, state) do
    {:noreply, detach_client(pid, state)}
  end

  defp buffer_message(msg, %{buffer_size: size, buffer_actual_size: size} = state) do
    buffer = :queue.in(msg, state.buffer)
    {_, buffer} = :queue.out(buffer)
    %{state | buffer: buffer}
  end

  defp buffer_message(msg, state) do
    buffer = :queue.in(msg, state.buffer)
    %{state | buffer: buffer, buffer_actual_size: state.buffer_actual_size + 1}
  end

  defp attach_client(client, state) do
    {detatch, clients} = 
      Enum.split_with(state.clients, &(&1.pid == client.pid))
    state = Enum.reduce(detatch, state, &detach_client(&1.pid, &2))
    
    %{state | clients: [client | clients]}
  end

  defp detach_client(pid, state) do
    {detach, clients} = 
      Enum.split_with(state.clients, &(&1.pid == pid or &1.task == pid))
    Enum.each(detach, &demonitor/1)
    if Process.alive?(pid) do
      Process.exit(pid, :normal)
    end
    %{state | clients: clients}
  end

  defp demonitor(%{monitor_ref: ref}), do: Process.demonitor(ref)

  defp trim_buffer(%{buffer_size: size, buffer_actual_size: actual, buffer: buffer} = state) 
    when size >= actual do
    trim = actual - size
    buffer = 
      Enum.reduce(1..trim, buffer, fn(_, buffer) ->  
        {_, buffer} = :queue.out(buffer)
        buffer
      end)
    %{state | buffer: buffer, buffer_actual_size: size}
  end

  defp trim_buffer(state), do: state

end
