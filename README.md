# ring_logger

[![CircleCI](https://circleci.com/gh/nerves-project/ring_logger.svg?style=svg)](https://circleci.com/gh/nerves-project/ring_logger)
[![Hex version](https://img.shields.io/hexpm/v/ring_logger.svg "Hex version")](https://hex.pm/packages/ring_logger)

This is an in-memory ring buffer backend for the [Elixir
Logger](https://hexdocs.pm/logger/Logger.html) with convenience methods for
accessing the logs from the IEx prompt.

Use cases:

* Get log messages in real-time over remote IEx sessions
* Grep and tail through log messages without setting up anything else
* Keep logs in limited resource environments
* Capture recent log events for error reports

As a bonus, `ring_logger` is nice to your IEx prompt. If you attach to the log
and are receiving messages as they're sent, they won't stomp what you're typing.

## Configuration

Add `ring_logger` to your projects dependencies in your `mix.exs`:

```elixir
  def deps do
    [{:ring_logger, "~> 0.6"}]
  end
```

Then configure the logger in your `config/config.exs`:

```elixir
use Mix.Config

# Add the RingLogger backend. This removes the
# default :console backend.
config :logger, backends: [RingLogger]

# Set the number of messages to hold in the circular buffer
config :logger, RingLogger, max_size: 1024

# You can also configure RingLogger.Client options to be used
# with every client by default
config :ring_logger,
  application_levels: %{my_app: :error},
  color: [debug: :yellow],
  level: :debug
```

Or you can start the backend manually by running the following:

```elixir
Logger.add_backend(RingLogger)
Logger.configure_backend(RingLogger, max_size: 1024)
```

## IEx session usage

See the example project for a hands-on walk-through of using the logger. Read on
for the highlights.

Log messages aren't printed to the console by default. If you're seeing them,
they may be coming from Elixir's default `:console` logger.

To see log messages as they come in, call `RingLogger.attach()` and then to make
the log messages stop, call `RingLogger.detach()`. The `attach` method takes
options if you want to limit the log level, change the formatting, etc.

Here's an example:

```elixir
iex> Logger.add_backend(RingLogger)
{:ok, #PID<0.199.0>}
iex> Logger.remove_backend(:console)
:ok
iex> RingLogger.attach
:ok
iex> require Logger
iex> Logger.info("hello")
:ok

14:04:52.516 [info]  hello
```

This probably isn't too exciting until you see that it works on remote shells as
well (the `:console` logger doesn't do this).

Say you prefer polling for log messages rather than having them print over your
console at random times. If you're still attached, then `detach` and `next`:

```elixir
iex> RingLogger.detach
:ok
iex> Logger.info("Hello logger, how are you?")
:ok
iex> Logger.info("It's a nice day. Wouldn't you say?")
:ok
iex> RingLogger.next

14:04:52.516 [info]  hello

14:11:54.397 [info]  Hello logger, how are you?

14:12:09.180 [info]  It's a nice day. Wouldn't you say?
:ok
iex> RingLogger.next
:ok
```

If you only want to see the most recent entries, run `tail`:

```elixir
iex> RingLogger.tail

14:04:52.516 [info]  hello

14:11:54.397 [info]  Hello logger, how are you?

14:12:09.180 [info]  It's a nice day. Wouldn't you say?
:ok
```

You can also `grep`:

```elixir
iex> RingLogger.grep(~r/[Nn]eedle/)

16:55:41.614 [info]  Needle in a haystack
```

## Module and Application Level Filtering

If you want to filter a module or modules at a particular level you pass a map
where the key is the module name and value in the level into the
`:module_levels` option to `RingLogger.attach/1`.

For example:

```elixir
iex> RingLogger.attach(module_levels: %{MyModule => :info})
```

This will ignore all the `:debug` messages from `MyModule`.

Also, it allows for filtering the whole project on a higher level, but a
particular module, or a subset of modules, to log at a lower level like so:

```elixir
iex> RingLogger.attach(module_levels: %{MyModule => :debug}, level: :warn)
```

In the example above log messages at the `:debug` level will be logged, but
every other module will be logging at the `:warn` level. You can also turn off a
module's logging completely by specifying `:none`.

Additionally, you can specify the same options at the application level to
disable logging for all its modules using the `:application_levels` option
with OTP application names as the key:

```elixir
iex> RingLogger.attach(application_levels: %{my_app: :info})
```

`module_levels` takes precedence in the case of including both module and
application level filtering:

```elixir
iex> RingLogger.attach(application_levels: %{my_app: :info}, module_levels: %{MyApp.Important => :debug})
```

In the above example, all modules of `:my_app` with have a level of `:info` except
for `MyApp.Important`, which will have a level of `:debug`.

As a note if the Elixir `Logger` level is set too low you will miss some log
messages.

## Saving the log

By design, `RingLogger` doesn't save logs. It can be convenient to share the
current log buffer for later analysis:

```elixir
iex> RingLogger.save("/tmp/log.txt")
:ok
```

Log messages are formatted the same way as the `RingLogger` functions that
output to the console.

## Formatting

If you want to use a specific string format with the built in Elixir
Logger.Formatter, you can pass that as the `:format` option to
`RingLogger.attach/1`.

If you want to use a custom formatter function, you can pass it through the
`:format` option to `RingLogger.attach/1` instead.

For example, to print the file and line number of each log message, you could
define a function as follows:

```elixir
defmodule CustomFormatter do
  def format(_level, message, _timestamp, metadata) do
    "#{message} #{metadata[:file]}:#{metadata[:line]}\n"
  rescue
    _ -> message
  end
end
```

and attach to the RingLogger with:

```elixir
iex> RingLogger.attach(format: {CustomFormatter, :format}, metadata: [:file, :line])
:ok
iex> require Logger
Logger
iex> Logger.info("Important message!")
:ok
Important message! iex:4
```

Within an application, the `iex:4` would be the source file path and line number.

See [Logger custom formatting](https://hexdocs.pm/logger/Logger.html#module-custom-formatting)
for more information.

## Programmatic usage

It can be useful to get a snapshot of the log when an unexpected event occurs.
The commandline functions demonstrated above are available, but you can also get
the raw log entries by calling `RingLogger.get/0`:

```elixir
iex> RingLogger.get
[
  debug: {Logger, "8", {{2018, 2, 5}, {17, 44, 7, 675}},
   [
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "ring_logger/example/lib/example.ex",
     line: 11
   ]},
  debug: {Logger, "9", {{2018, 2, 5}, {17, 44, 8, 676}},
   [
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "ring_logger/example/lib/example.ex",
     line: 11
   ]},
  debug: {Logger, "10", {{2018, 2, 5}, {17, 44, 9, 677}},
   [
     pid: #PID<0.139.0>,
     application: :example,
     module: Example,
     function: "log/1",
     file: "ring_logger/example/lib/example.ex",
     line: 11
   ]}
]
```
