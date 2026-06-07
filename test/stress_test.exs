defmodule StressTest do
  use ExUnit.Case, async: false

  require Logger

  @default_pattern "\n$time $metadata[$level] $message\n"
  @ring_size 11

  setup do
    {:ok, pid} = RingLogger.TestIO.start(self())

    old_level = :logger.get_primary_config().level
    :logger.set_primary_config(:level, :all)

    # Flush any latent messages in the Logger to avoid them polluting
    # our tests
    Logger.flush()

    :ok = RingLogger.add(max_size: @ring_size)

    on_exit(fn ->
      RingLogger.TestIO.stop(pid)
      _ = RingLogger.remove()
      :logger.set_primary_config(:level, old_level)
    end)

    {:ok, [io: pid]}
  end

  defp handshake_log(io, level, message) do
    Logger.log(level, message)
    assert_receive {:io, msg}
    assert String.contains?(msg, to_string(level))

    flattened_message = IO.chardata_to_string(message)
    assert String.contains?(msg, flattened_message)
    io
  end

  @tag timeout: 120_000
  test "next a lot", %{io: io} do
    :ok = RingLogger.attach(io: io, format: @default_pattern)
    handshake_log(io, :debug, "Hello")

    for i <- 1..211 do
      for k <- 0..@ring_size do
        RingLogger.Server.clear()
        RingLogger.reset()

        if k > 0 do
          # Fill with 0 or more starter messages and receive them
          for j <- 1..k do
            handshake_log(io, :info, "#{k}: starter #{j}")
          end

          :ok = RingLogger.next()
          assert_receive {:io, messages}, 100

          for j <- 1..k do
            assert messages =~ "[info] #{k}: starter #{j}"
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
