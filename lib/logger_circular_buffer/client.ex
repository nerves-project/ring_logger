defmodule Logger.CircularBuffer.Client do
  defstruct pid: nil,
            task: nil,
            monitor_ref: nil,
            config: []

  def init(pid, task, config) do
    colors = configure_colors(config)
    metadata = Keyword.get(config, :metadata, []) |> configure_metadata()
    format = Logger.Formatter.compile(Keyword.get(config, :format))
    io = Keyword.get(config, :io) || :stdio

    config =
      config
      |> Keyword.put(:format, format)
      |> Keyword.put(:metadata, metadata)
      |> Keyword.put(:colors, colors)
      |> Keyword.put(:io, io)

    %__MODULE__{
      pid: pid,
      task: task,
      monitor_ref: Process.monitor(task),
      config: config
    }
  end

  def loop() do
    receive do
      {:log, {level, _} = msg, config} ->
        min_level = Keyword.get(config, :level)

        if meet_level?(level, min_level) do
          log(msg, config)
        end

      _ ->
        :ok
    end

    loop()
  end

  def log(message, config) do
    item = 
      format_message(message, config)
      |> IO.iodata_to_binary()
    IO.binwrite(config[:io], item)
  end

  def format_message({level, {_, msg, ts, md}}, config) do
    metadata = take_metadata(md, config[:metadata])
    config[:format]
    |> Logger.Formatter.format(level, msg, ts, metadata)
    |> color_event(level, config[:colors], md)
  end

  ## Helpers

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
