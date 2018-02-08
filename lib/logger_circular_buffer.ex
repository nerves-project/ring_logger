defmodule LoggerCircularBuffer do
  @behaviour :gen_event

  alias LoggerCircularBuffer.{Server, Client}

  #
  # API
  #

  @doc """
  Attach the current IEx session to the logger. It will start printing log messages.

  Options include:
  * `:io` - Defaults to `:stdio`
  * `:colors` -
  * `:metadata` - A KV list of additional metadata
  * `:format` - A custom format string
  """
  defdelegate attach(opts \\ []), to: Server

  @doc """
  Detach the current IEx session from the logger.
  """
  defdelegate detach(), to: Server

  @doc """
  Get all log messages at the specified index and later.
  """
  defdelegate get(index \\ 0), to: Server

  @doc """
  Update the loggers configuration.

  Options include:
  * `:buffer_size` - the number of log messages to store at a time
  """
  defdelegate configure(opts), to: Server

  @doc """
  Helper method for formatting log messages per the current client's
  configuration.
  """
  defdelegate format_message(message, config), to: Client

  #
  # Logger backend callbacks
  #
  def init(__MODULE__) do
    {:ok, init({__MODULE__, []})}
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)
    Server.start_link(opts)
    {:ok, configure(opts)}
  end

  def handle_call({:configure, opts}, _state) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)
    {:ok, :ok, configure(opts)}
  end

  def handle_event(:flush, state) do
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
