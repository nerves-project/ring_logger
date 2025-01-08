defmodule RingLogger.ViewerTest do
  use ExUnit.Case, async: false

  require Logger

  @default_pattern "\n$time $metadata[$level] $message\n"

  setup do
    Logger.remove_backend(:console)

    Logger.flush()

    Logger.add_backend(RingLogger)

    Logger.configure_backend(RingLogger,
      max_size: 10,
      format: @default_pattern,
      metadata: [:request_id, :file, :line, :module, :function, :time],
      buffers: [],
      persist_path: "/temp/file.log",
      persist_seconds: 1_000
    )

    on_exit(fn ->
      File.rm("/temp/file.log")
      Logger.remove_backend(RingLogger)
    end)

    {:ok, %{state: nil}}
  end

  test "Ringlogger.view/1 with multiple commands ; separated", %{state: _state} do
    Logger.debug("blofeld debug level sample msg", application: :blofeld_firmware)
    Logger.warning("blofeld warn level sample msg", application: :telit_modem)
    Logger.info("blofeld info level sample msg", application: :peridiod)
    Logger.critical("blofeld critical level sample msg", application: nil)
    Logger.emergency("blofeld emergency level sample msg", application: :Vintage_Net)
    Logger.debug("---------enter q to exit out of given test-----", application: :User)

    assert :ok = RingLogger.Viewer.view("a telit_modem;l debug; q")
  end

  test "Ringlogger.view/1 with invalid command format", %{state: _state} do
    Logger.debug("blofeld debug level sample msg", application: :blofeld_firmware)
    Logger.warning("blofeld warn level sample msg", application: :telit_modem)
    Logger.info("blofeld info level sample msg", application: :peridiod)
    Logger.critical("blofeld critical level sample msg", application: nil)
    Logger.emergency("blofeld emergency level sample msg", application: :Vintage_Net)
    Logger.info("---------enter q to exit out of given test-----", application: :User)

    # observe in logs you wont find (debug) anywhere writtem at the bottom left corner
    assert :ok = RingLogger.Viewer.view("r l debug; q")
  end

  test "a command with single application", %{state: _state} do
    Logger.debug("blofeld debug level sample msg", application: :blofeld_firmware)
    Logger.warning("blofeld warn level sample msg", application: :telit_modem)
    Logger.info("blofeld info level sample msg", application: :peridiod)
    Logger.critical("blofeld critical level sample msg", application: nil)
    Logger.emergency("blofeld emergency level sample msg", application: :Vintage_Net)
    Logger.debug("---------enter q to exit out of given test-----", application: :User)

    assert :ok = RingLogger.Viewer.view("a telit_modem; q")
  end

  test "a command with multiple applications", %{state: _state} do
    Logger.debug("blofeld debug level sample msg",
      application: :blofeld_firmware,
      time: 1_735_140_308_331_070
    )

    Logger.warning("blofeld warn level sample msg", application: :telit_modem)
    Logger.info("blofeld info level sample msg", application: :peridiod)
    Logger.critical("blofeld critical level sample msg", application: nil)
    Logger.emergency("blofeld emergency level sample msg", application: :Vintage_Net)
    Logger.info("---------enter q to exit out of given test-----", application: :User)

    assert :ok = RingLogger.Viewer.view("a nil blofeld_firmware peridiod; q")
  end

  test "goto date command with Invalid arguments using Ringlogger.view/1 command", %{
    state: _state
  } do
    Logger.debug("blofeld debug level sample msg",
      application: :blofeld_firmware,
      time: 1_735_160_108_000_011
    )

    Logger.warning("blofeld warn level sample msg", application: :telit_modem)
    Logger.info("blofeld info level sample msg", application: :peridiod)
    Logger.critical("blofeld critical level sample msg", application: nil)
    Logger.emergency("blofeld emergency level sample msg", application: :Vintage_Net)

    Logger.info("---------enter q to exit out of given test-----",
      application: :User,
      time: 1_735_160_108_000_011
    )

    assert :ok = RingLogger.Viewer.view("d 2024-1; q")
  end

  test "goto date command with valid arguments using Ringlogger.view/1 command", %{state: _state} do
    Logger.debug("blofeld debug level sample msg",
      application: :blofeld_firmware,
      time: 1_735_160_108_000_011
    )

    Logger.warning("blofeld warn level sample msg", application: :telit_modem)
    Logger.info("blofeld info level sample msg", application: :peridiod)
    Logger.critical("blofeld critical level sample msg", application: nil)
    Logger.emergency("blofeld emergency level sample msg", application: :Vintage_Net)

    Logger.info("---------enter q to exit out of given test-----",
      application: :User,
      time: 1_735_160_108_000_011
    )

    assert :ok = RingLogger.Viewer.view("d 2024-12-25 20:55:08; q")
  end
end
