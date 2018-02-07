# Example

Start the example app:

```bash
iex --name node1@127.0.0.1 -S mix
```

Create a remote connection in another terminal

```bash
iex --name node2@127.0.0.1 --remsh node1@127.0.0.1
```

Attach to the remote console logger:

```elixir
iex(node2@127.0.0.1)> LoggerCircularBuffer.attach
```

Detach from the remote console logger:

```elixir
iex(node2@127.0.0.1)> LoggerCircularBuffer.detach
```

Get all of the log messages:

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

Format the log:

```elixir
iex(node1@127.0.0.1)> {:ok, client} = LoggerCircularBuffer.attach
# ...
iex(node2@127.0.0.1)> buffer = LoggerCircularBuffer.get
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
iex(node1@127.0.0.1)> Enum.map(buffer, & LoggerCircularBuffer.Client.format_message(&1, client.config))
["\e[36m\n17:51:56.680 [debug] 8\n\e[0m",
 "\e[36m\n17:51:57.681 [debug] 9\n\e[0m",
 "\e[36m\n17:51:58.682 [debug] 10\n\e[0m"]
```
