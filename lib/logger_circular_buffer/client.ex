defmodule LoggerCircularBuffer.Client do
  alias LoggerCircularBuffer.Config

  defstruct pid: nil,
            task: nil,
            monitor_ref: nil,
            io: nil,
            config: nil

  def init(pid, task, config \\ nil) do
    %__MODULE__{
      pid: pid,
      task: task,
      monitor_ref: Process.monitor(task),
      config: Config.init(config)
    }
  end

  def loop() do
    receive do
      {:log, {level, _} = msg, %{config: config}} ->
        min_level = Map.get(config, :level)

        if meet_level?(level, min_level) do
          log(msg, config)
        end

      _ ->
        :ok
    end

    loop()
  end

  def log(message, %Config{} = config) do
    item = format_message(message, config)

    IO.binwrite(config.io, item)
  end

  def format_message({level, {_, msg, ts, md}}, %Config{} = config) do
    metadata = take_metadata(md, config.metadata)

    config
    |> Map.get(:format)
    |> Logger.Formatter.format(level, msg, ts, metadata)
    |> color_event(level, config.colors, md)
  end

  ## Helpers

  defp meet_level?(_lvl, nil), do: true

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp take_metadata(metadata, :all), do: metadata

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
  end

  defp color_event(data, _level, %{enabled: false}, _md), do: data

  defp color_event(data, level, %{enabled: true} = colors, md) do
    color = md[:ansi_color] || Map.fetch!(colors, level)
    [IO.ANSI.format_fragment(color, true), data | IO.ANSI.reset()]
  end
end
