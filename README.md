# ring_logger

[![CircleCI](https://circleci.com/gh/nerves-project/ring_logger.svg?style=svg)](https://circleci.com/gh/nerves-project/ring_logger)
[![Hex version](https://img.shields.io/hexpm/v/ring_logger.svg "Hex version")](https://hex.pm/packages/ring_logger)

This is a circular buffer backend for the [Elixir
Logger](https://hexdocs.pm/logger/Logger.html) for use in environments where
saving logs to disk or forwarding them over the network are not desired. It also
has convenience methods for interacting with the log from the IEx prompt.

## Configuration

First, add `ring_logger` to your projects dependencies in your
`mix.exs`:

```elixir
  def deps do
    [{:ring_logger, "~> 0.3.0"}]
  end
```

Then configure the logger in your `config/config.exs`:

```elixir
use Mix.Config

# Add the RingLogger backend. This removes the
# default :console backend.
config :logger, backends: [RingLogger]

# Set the number of messages to hold in the circular buffer
config :logger, RingLogger, max_size: 100
```

Or you can start the backend manually by running the following:

```elixir
Logger.add_backend(RingLogger)
Logger.configure(RingLogger, max_size: 100)
```

## IEx session usage

See the example project for a hands-on walkthrough of using the logger. Read on
for the highlights.

Log messages aren't printed to the console by default. If you're seeing them,
they may be coming from Elixir's default `:console` logger.

To see log messages as they come in, call `RingLogger.attach()` and
then to make the log messages stop, call `RingLogger.detach()`. The
`attach` method takes options if you want to limit the log level, change the
formatting, etc.

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
console at random times. If you're still attached, then `detach` and `tail`:

```elixir
iex> RingLogger.detach
:ok
iex> Logger.info("Hello logger, how are you?")
:ok
iex> Logger.info("It's a nice day. Wouldn't you say?")
:ok
iex> RingLogger.tail

14:04:52.516 [info]  hello

14:11:54.397 [info]  Hello logger, how are you?

14:12:09.180 [info]  It's a nice day. Wouldn't you say?
:ok
```

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
