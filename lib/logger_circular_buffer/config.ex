defmodule Logger.CircularBuffer.Config do
  defstruct colors: nil,
            metadata: nil,
            format: nil,
            io: nil

  def init(config \\ []) do
    %__MODULE__{
      io: Keyword.get(config, :io, :stdio),
      colors: configure_colors(config),
      metadata: Keyword.get(config, :metadata, []) |> configure_metadata(),
      format: Logger.Formatter.compile(Keyword.get(config, :format))
    }
  end

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp configure_colors(config) do
    colors = Keyword.get(config, :colors, [])

    %{
      debug: Keyword.get(colors, :debug, :cyan),
      info: Keyword.get(colors, :info, :normal),
      warn: Keyword.get(colors, :warn, :yellow),
      error: Keyword.get(colors, :error, :red),
      enabled: Keyword.get(colors, :enabled, IO.ANSI.enabled?())
    }
  end
end
