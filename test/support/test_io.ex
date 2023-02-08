defmodule RingLogger.TestIO do
  @moduledoc false
  use GenServer

  @spec start(pid()) :: GenServer.on_start()
  def start(callback) do
    GenServer.start(__MODULE__, callback)
  end

  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @impl GenServer
  def init(callback) do
    {:ok, callback}
  end

  @impl GenServer
  def handle_info({:io_request, from, reply_as, {:put_chars, _encoding, chars}}, callback) do
    send(callback, {:io, chars})
    reply(from, reply_as, :ok)
    {:noreply, callback}
  end

  defp reply(from, reply_as, reply) do
    send(from, {:io_reply, reply_as, reply})
  end
end
