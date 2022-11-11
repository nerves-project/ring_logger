defmodule RingLogger.LogEntry do
  @moduledoc false

  @typedoc "A tuple holding a raw, unformatted log entry"
  @type t :: {Logger.level(), message_tuple}

  @type message_tuple :: {module(), Logger.message(), Logger.Formatter.time(), Logger.metadata()}

  @spec new(Logger.level(), message_tuple()) :: t()
  def new(level, message_tuple) do
    {level, message_tuple}
  end

  @spec put_index(t(), non_neg_integer()) :: t()
  def put_index({level, {mod, msg, ts, md}}, index) do
    {level, {mod, msg, ts, Keyword.put(md, :index, index)}}
  end
end
