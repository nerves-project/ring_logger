defmodule RingLogger.Persistence do
  @moduledoc false

  @spec load(String.t()) :: [RingLogger.entry()] | {:error, atom()}
  def load(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term()
  rescue
    error in File.Error ->
      {:error, error.reason}

    ArgumentError ->
      {:error, :corrupted}
  end

  @spec save(String.t(), [RingLogger.entry()]) :: :ok | {:error, atom()}
  def save(path, logs) do
    File.write!(path, :erlang.term_to_binary(logs))
  rescue
    error in File.Error ->
      {:error, error.reason}
  end
end
