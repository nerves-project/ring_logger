defmodule RingLogger.TestCustomFormatter do
  def format(_level, message, _timestamp, metadata) do
    "index=#{metadata[:index]} #{message}"
  end
end
