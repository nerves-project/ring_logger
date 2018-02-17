defmodule RingLogger.Server do
  use GenServer

  alias RingLogger.Client

  @opts [:max_size]

  defmodule State do
    @moduledoc false

    @default_max_size 100

    defstruct clients: [],
              buffer: :queue.new(),
              size: 0,
              max_size: @default_max_size,
              index: 0
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop() do
    GenServer.stop(__MODULE__)
  end

  def configure(opts) do
    GenServer.call(__MODULE__, {:configure, opts})
  end

  def attach_client(client_pid) do
    GenServer.call(__MODULE__, {:attach, client_pid})
  end

  def detach_client(client_pid) do
    GenServer.call(__MODULE__, {:detach, client_pid})
  end

  @spec get(non_neg_integer()) :: [RingLogger.entry()]
  def get(start_index \\ 0) do
    GenServer.call(__MODULE__, {:get, start_index})
  end

  def log(msg) do
    GenServer.cast(__MODULE__, {:log, msg})
  end

  def init(opts) do
    {:ok, merge_opts(opts, %State{})}
  end

  def handle_call({:configure, opts}, _from, state) do
    {:reply, :ok, merge_opts(opts, state)}
  end

  def handle_call({:attach, client_pid}, _from, state) do
    {:reply, :ok, attach_client(client_pid, state)}
  end

  def handle_call({:detach, pid}, _from, state) do
    {:reply, :ok, detach_client(pid, state)}
  end

  def handle_call({:get, start_index}, _from, state) do
    resp =
      cond do
        start_index <= state.index ->
          :queue.to_list(state.buffer)

        start_index >= state.index + state.size ->
          []

        true ->
          {_, buffer_range} = :queue.split(start_index - state.index, state.buffer)
          :queue.to_list(buffer_range)
      end

    {:reply, resp, state}
  end

  def handle_cast({:log, msg}, state) do
    {:noreply, push(msg, state)}
  end

  def handle_info({:DOWN, _ref, _, pid, _reason}, state) do
    {:noreply, detach_client(pid, state)}
  end

  def terminate(_reason, state) do
    Enum.each(state.clients, fn {client_pid, _ref} -> Client.stop(client_pid) end)
    :ok
  end

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

  defp merge_opts(opts, state) do
    opts =
      opts
      |> Keyword.take(@opts)
      |> Enum.into(%{})

    state
    |> Map.merge(opts)
    |> trim
  end

  defp trim(%{max_size: max_size, size: size, buffer: buffer} = state)
       when size > max_size do
    trim = max_size - size

    buffer = Enum.reduce(1..trim, buffer, fn _, buf -> :queue.drop(buf) end)

    %{state | buffer: buffer, size: size}
  end

  defp trim(state), do: state

  defp push({level, {mod, msg, ts, md}}, state) do
    index = state.index + state.size
    msg = {level, {mod, msg, ts, Keyword.put(md, :index, index)}}

    state =
      if state.size == state.max_size do
        buffer = :queue.drop(state.buffer)
        %{state | buffer: buffer, index: state.index + 1}
      else
        %{state | size: state.size + 1}
      end

    Enum.each(state.clients, &send_log(&1, msg))
    %{state | buffer: :queue.in(msg, state.buffer)}
  end

  defp send_log({client_pid, _ref}, msg) do
    send(client_pid, {:log, msg})
  end
end
