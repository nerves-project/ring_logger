# Example

This example starts a process that repeatedly logs messages. You can run it
normally (`iex -S mix`) or via a remote shell. Since this logger is more
interesting for the remote access, we'll demo that:

First, start the example application as `node1`:

```bash
iex --name node1@0.0.0.0 -S mix
```

Create another terminal and remote shell into `node1`:

```bash
iex --name node2@0.0.0.0 --remsh node1@0.0.0.0
```

At this point, you should see `:console` logger messages scrolling by on
`node1`. Your remote shell session on `node2` will be nice and quiet. In real
use, you will probably consider disabling the `:console` logger, but it is
informative for this example.

Now, on `node2`, try attaching to the log:

```elixir
iex(node1@0.0.0.0)> LoggerCircularBuffer.attach
```

You should see log messages now. When you're tired of watching them, detach:

```elixir
iex(node1@0.0.0.0)> LoggerCircularBuffer.detach
```

If you're the type of person who prefers to poll their logs manually, you can do
that too:

```elixir
iex(node1@0.0.0.0)5> LoggerCircularBuffer.tail

12:48:43.142 [debug] 285

12:48:44.143 [debug] 286
```

`LoggerCircularBuffer.tail` keeps track of your position in the log so only new
messages get printed. If you create a new remote shell session, the position is
reset. You can also call `LoggerCircularBuffer.reset` to reset the position
manually. Keep in mind that logs are stored in a ring buffer, so as soon as the
log hits the maximum configured length, old messages will be discarded.

