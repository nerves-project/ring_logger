defmodule StressTest do
  use ExUnit.Case, async: false

  require Logger

  @ring_size 11

  setup do
    {:ok, pid} = RingLogger.TestIO.start(self())
    Logger.remove_backend(:console)

    # Flush any latent messages in the Logger to avoid them polluting
    # our tests
    Logger.flush()

    Logger.add_backend(RingLogger)
    Logger.configure_backend(RingLogger, max_size: @ring_size)

    on_exit(fn ->
      RingLogger.TestIO.stop(pid)
      Logger.remove_backend(RingLogger)
    end)

    {:ok, [io: pid]}
  end

  @doc """
  Ensure that a log message makes it way through the logger processes.

  The RingLogger needs to be attached for this to work. This makes
  logging synchronous so that we can test tail, next, grep, etc. that
  rely on the messages being received by RingLogger.
  """
  def handshake_log(io, level, message) do
    Logger.log(level, message)
    assert_receive {:io, msg}
    assert String.contains?(msg, to_string(level))

    flattened_message = IO.iodata_to_binary(message)
    assert String.contains?(msg, flattened_message)
    io
  end

  @tag timeout: 120_000
  test "next a lot", %{io: io} do
    :ok = RingLogger.attach(io: io)
    handshake_log(io, :debug, "Hello")

    for i <- 1..211 do
      for k <- 0..@ring_size do
        RingLogger.Server.clear()

        if k > 0 do
          # Fill with 0 or more starter messages and receive them
          for j <- 1..k do
            handshake_log(io, :info, "#{k}: starter #{j}")
          end

          :ok = RingLogger.next()
          assert_receive {:io, messages}, 100

          for j <- 1..k do
            assert messages =~ "[info]  #{k}: starter #{j}"
          end
        end

        # Now add i messages and receive them
        for j <- 1..i do
          handshake_log(io, :debug, "#{k}: log #{j} of #{i}")
        end

        :ok = RingLogger.next()
        assert_receive {:io, messages}, 100

        # There shouldn't be any starter messages
        refute messages =~ "starter"

        # Check for the last @ring_size messages that we logged
        ring_first = max(1, i - @ring_size + 1)

        for j <- ring_first..i do
          assert messages =~ "[debug] #{k}: log #{j} of #{i}"
        end

        # Check for messages that should have dropped out of the ring
        if ring_first > 1 do
          for j <- 1..(ring_first - 1) do
            refute messages =~ "log #{j} of #{i}"
          end
        end
      end
    end
  end
end
