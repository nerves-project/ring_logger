defmodule Example do
  require Logger

  def start(_type, _args) do
    spawn(fn -> log(0) end)
    {:ok, self()}
  end

  def log(num) do
    num = num + 1
    Logger.debug("#{num}")
    :timer.sleep(1000)
    log(num)
  end
end
