# logger_circular_buffer

[![CircleCI](https://circleci.com/gh/nerves-project/logger_circular_buffer.svg style=svg)](https://circleci.com/gh/nerves-project/logger_circular_buffer)
[![Hex version](https://img.shields.io/hexpm/v/logger_circular_buffer.svg "Hex version")](https://hex.pm/packages/logger_circular_buffer)

This is a circular buffer backend for the [Elixir
Logger](https://hexdocs.pm/logger/Logger.html) with support for polling logs and
streaming them to IEx sessions both local and remote.

## Configuration

First, add `logger_circular_buffer` to your projects dependencies in your
`mix.exs`:

```elixir
  def deps do
    [{:logger_circular_buffer, "~> 0.2.0"}]
  end
```

Then configure the logger in your `config/config.exs`:

```elixir
use Mix.Config

# Add the LoggerCircularBuffer backend. This removes the
# default :console backend.
config :logger, backends: [LoggerCircularBuffer]

# Set the number of messages to hold in the circular buffer
config :logger, LoggerCircularBuffer, buffer_size: 100
```

Or you can start the backend manually by running the following:

```elixir
Logger.add_backend(LoggerCircularBuffer)
Logger.configure(LoggerCircularBuffer, buffer_size: 100)
```

## Usage

To see log messages as they come in, call `attach/0` to have them sent to your
current IEx session. This works in a similar way to the `:console` logger but
with the added bonus of working on remote IEx shells as well.

```elixir
iex(node2@127.0.0.1)> LoggerCircularBuffer.attach
```

When you've had enough, call `detach/0`:

```elixir
iex(node2@127.0.0.1)> LoggerCircularBuffer.detach
```

Other times, it's useful to get the logs programmatically. For example, if
circumstances don't permit sending logs continuously to a remote server for
review, but you'd like to send a snapshot when a notable event happens:

```elixir
iex(node2@127.0.0.1)> LoggerCircularBuffer.get
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

Formatting is nice. You can apply formatting like this:

```elixir
iex> config = LoggerCircularBuffer.Config.init(colors: [enabled: false])
%LoggerCircularBuffer.Config{
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
iex> {:ok, buffer} = LoggerCircularBuffer.get
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
iex> Enum.map(buffer, & LoggerCircularBuffer.Client.format_message(&1, config)) |> Enum.map(&IO.iodata_to_binary/1)
["\n17:51:56.680 [debug] 8\n",
 "\n17:51:57.681 [debug] 9\n",
 "\n17:51:58.682 [debug] 10\n"]
```
