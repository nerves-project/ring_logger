# Logger.CircularBuffer
A circular buffer backend for Elixir Logger with support for IO streaming.

[![CircleCI](https://circleci.com/gh/nerves-project/logger_circular_buffer.svg?style=svg)](https://circleci.com/gh/nerves-project/logger_circular_buffer)
[![Hex version](https://img.shields.io/hexpm/v/logger_circular_buffer.svg "Hex version")](https://hex.pm/packages/logger_circular_buffer)

## Configuration

Configuring via Application config
```elixir
# config/config.exs
use Mix.Config

config :logger, backends: [Logger.CircularBuffer]

config :logger, Logger.CircularBuffer, buffer_size: 100
```

Startng Manually
```elixir
Logger.add_backend(Logger.CircularBuffer)
Logger.configure(Logger.CircularBuffer, buffer_size: 100)
```

## Usage

Get the remote console buffer
```elixir
iex(node2@127.0.0.1)> Logger.CircularBuffer.get
[
  debug: {Logger, "8", {{2018, 2, 5}, {17, 44, 7, 675}},
   [
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "/home/jschneck/dev/logger_circular_buffer/example/lib/example.ex",
     line: 11
   ]},
  debug: {Logger, "9", {{2018, 2, 5}, {17, 44, 8, 676}},
   [
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "/home/jschneck/dev/logger_circular_buffer/example/lib/example.ex",
     line: 11
   ]},
  debug: {Logger, "10", {{2018, 2, 5}, {17, 44, 9, 677}},
   [
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "/home/jschneck/dev/logger_circular_buffer/example/lib/example.ex",
     line: 11
   ]}
]
```

The buffer is stored as unformatted messages and formatting is applies to the
connected clients. You can apply formatting to the buffer afterwards like this:
```elixir
iex> config = Logger,CircularBuffer.Config.init(colors: [enabled: false])
%Logger.CircularBuffer.Config{
  colors: %{
    debug: :cyan,
    enabled: true,
    error: :red,
    info: :normal,
    warn: :yellow
  },
  format: ["\n", :time, " ", :metadata, "[", :level, "] ", :levelpad, :message,
   "\n"],
  io: :stdio,
  metadata: []
}
iex> {:ok, buffer} = Logger.CircularBuffer.get
[
  debug: {Logger, "8", {{2018, 2, 5}, {17, 44, 7, 675}},
   [
     index: 8,
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "/home/jschneck/dev/logger_circular_buffer/example/lib/example.ex",
     line: 11
   ]},
  debug: {Logger, "9", {{2018, 2, 5}, {17, 44, 8, 676}},
   [
     index: 9,
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "/home/jschneck/dev/logger_circular_buffer/example/lib/example.ex",
     line: 11
   ]},
  debug: {Logger, "10", {{2018, 2, 5}, {17, 44, 9, 677}},
   [
     index: 10,
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "/home/jschneck/dev/logger_circular_buffer/example/lib/example.ex",
     line: 11
   ]}
]
iex> Enum.map(buffer, & Logger.CircularBuffer.Client.format_message(&1, config)) |> Enum.map(&IO.iodata_to_binary/1)
["\n17:51:56.680 [debug] 8\n",
 "\n17:51:57.681 [debug] 9\n",
 "\n17:51:58.682 [debug] 10\n"]
```

Attaching IO to the circular buffer
```elixir
iex(node2@127.0.0.1)> Logger.CircularBuffer.attach
```

Detaching IO from the circular buffer
```elixir
iex(node2@127.0.0.1)> Logger.CircularBuffer.detach
```
