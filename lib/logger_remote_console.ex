defmodule Logger.RemoteConsole do
  @behaviour :gen_event

  alias Logger.RemoteConsole.Server

  defdelegate attach(opts \\ []), to: Server
  defdelegate detach(), to: Server
  defdelegate get_buffer(), to: Server
  defdelegate configure(opts), to: Server

  def flush_buffer do
    Logger.flush()
  end

  def init(__MODULE__) do
    {:ok, init({__MODULE__, []})}
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    Server.start_link(opts)
    {:ok, configure(opts)}
  end

  def handle_call({:configure, opts}, _state) do
    {:ok, :ok, configure(opts)}
  end

  def handle_event(:flush, state) do
    Server.flush_buffer()
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, _, _, _} = msg}, state) do
    Server.log({level, msg})
    {:ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

end
