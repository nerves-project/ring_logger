defmodule RingLogger.PersistenceTest do
  use ExUnit.Case, async: false

  alias RingLogger.Persistence

  @persistence_log_name "test/persistence_test.log"

  test "saving logs" do
    File.rm(@persistence_log_name)

    logs = [
      %{
        level: :debug,
        module: Logger,
        message: "Foo",
        timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
        metadata: []
      },
      %{
        level: :debug,
        module: Logger,
        message: "Bar",
        timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
        metadata: []
      }
    ]

    :ok = Persistence.save(@persistence_log_name, logs)

    assert File.exists?(@persistence_log_name)

    File.rm(@persistence_log_name)
  end

  test "loading logs" do
    File.rm(@persistence_log_name)

    logs = [
      %{
        level: :debug,
        module: Logger,
        message: "Foo",
        timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
        metadata: []
      },
      %{
        level: :debug,
        module: Logger,
        message: "Bar",
        timestamp: {{2023, 2, 8}, {13, 58, 31, 343}},
        metadata: []
      }
    ]

    :ok = Persistence.save(@persistence_log_name, logs)

    loaded_logs = Persistence.load(@persistence_log_name)

    assert logs == loaded_logs

    File.rm(@persistence_log_name)
  end

  test "file was corrupted" do
    File.write!(@persistence_log_name, "bad file")

    assert {:error, :corrupted} = Persistence.load(@persistence_log_name)

    File.rm(@persistence_log_name)
  end

  test "file doesn't exist" do
    assert {:error, :enoent} = Persistence.load(@persistence_log_name)
  end
end
