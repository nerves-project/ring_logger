defmodule RingLogger.ViewerTest do
  @moduledoc """
  Ringlogger.Viewer Module contains all private functions except view() and newly created function parse_launch_command.
  Thus test cases tries to showcase the updated state of the Ringlogger.Viewer module only not the visual implementation of the same.
  """

  use ExUnit.Case, async: false

  alias RingLogger.Viewer

  require Logger

  @default_pattern "\n$time $metadata[$level] $message\n"

  @init_state %{
    current_screen: :list,
    running: true,
    last_cmd_string: nil,
    current_page: 0,
    last_page: 0,
    per_page: 0,
    screen_dims: %{w: 0, h: 0},
    lowest_log_level: nil,
    before_boot: true,
    grep_filter: nil,
    applications_filter: [],
    raw_logs: []
  }

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

  test "Viewer.parse_launch_cmd/2 with multiple commands ; separated" do
    cmd_string = "a telit_modem; l debug"
    state = Viewer.parse_launch_cmd(cmd_string, @init_state)
    assert [:telit_modem] == state.applications_filter
    assert :debug == state.lowest_log_level
  end

  test "Viewer.parse_launch_cmd/2 with invalid format" do
    cmd_string = "r l debug; a"
    state = Viewer.parse_launch_cmd(cmd_string, @init_state)
    assert [] == state.applications_filter
  end

  test "a command with single application using parse_launch_cmd/2" do
    cmd_string = "a blofeld_firmware"
    state = Viewer.parse_launch_cmd(cmd_string, @init_state)
    assert [:blofeld_firmware] == state.applications_filter
  end

  test "a command with multiple applications using parse_launch_cmd/2" do
    cmd_string = "a blofeld_firmware telit_modem nil $kmsg"
    state = Viewer.parse_launch_cmd(cmd_string, @init_state)
    assert [:blofeld_firmware, :telit_modem, nil, :"$kmsg"] == state.applications_filter
  end

  test "goto date command with Valid arguments using Viewer.parse_launch_cmd/2 command" do
    cmd_string = "d 2024-12-25 20:55:08"
    state = Viewer.parse_launch_cmd(cmd_string, @init_state)

    assert [start_time: 1_735_160_108_000_000, end_time: 1_735_160_109_000_000] ==
             state.applications_filter
  end

  test "goto date command with invalid arguments using Viewer.parse_launch_cmd/2 command" do
    cmd_string = "d 2024-12-25 8"
    state = Viewer.parse_launch_cmd(cmd_string, @init_state)
    assert [] == state.applications_filter
  end
end
