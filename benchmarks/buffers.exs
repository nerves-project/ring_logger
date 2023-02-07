require Logger

Logger.remove_backend(:console)
Logger.add_backend(RingLogger)

Benchee.run(
  %{
    "one buffer" => {
      fn _input ->
        Logger.debug("Low priority")
        Logger.error("High priority")
      end,
      before_scenario: fn _input ->
        Logger.configure_backend(RingLogger, max_size: 1024, buffers: %{})
      end,
      after_scenario: fn _input ->
        IO.inspect Enum.count(RingLogger.get(0, 0))
      end
    },
    "multiple buffers" => {
      fn _input ->
        Logger.debug("Low priority")
        Logger.error("High priority")
      end,
      before_scenario: fn _input ->
        Logger.configure_backend(RingLogger, max_size: 1024, buffers: %{
          low_priority: %{
            levels: [:warning, :notice, :info, :debug],
            max_size: 1024
          },
          high_priority: %{
            levels: [:emergency, :alert, :critical, :error],
            max_size: 1024
          }
        })
      end,
      after_scenario: fn _input ->
        IO.inspect Enum.count(RingLogger.get(0, 0))
      end
    }
  },
  after_scenario: fn _input ->
    RingLogger.Server.clear()
  end
)
