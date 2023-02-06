defmodule RingLogger.Buffer do
  @moduledoc false

  defstruct [:name, :levels, :max_size, :circular_buffer]
end
