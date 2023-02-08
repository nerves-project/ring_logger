defmodule RingLogger.TestCustomFormatter do
  @moduledoc false

  @spec format(atom, term, Logger.Formatter.time(), keyword()) :: IO.chardata()
  def format(_level, message, _timestamp, metadata) do
    "index=#{metadata[:index]} #{message}"
  end
end
