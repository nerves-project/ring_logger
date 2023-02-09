defmodule RingLogger.PersistenceTest do
  use ExUnit.Case, async: false

  alias RingLogger.Persistence

  test "saving logs" do
    File.rm("test/persistence.log")

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

    :ok = Persistence.save("test/persistence.log", logs)

    assert File.exists?("test/persistence.log")

    File.rm("test/persistence.log")
  end

  test "loading logs" do
    File.rm("test/persistence.log")

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

    :ok = Persistence.save("test/persistence.log", logs)

    loaded_logs = Persistence.load("test/persistence.log")

    assert logs == loaded_logs

    File.rm("test/persistence.log")
  end

  test "file was corrupted" do
    File.write!("test/persistence.log", "bad file")

    assert {:error, :corrupted} = Persistence.load("test/persistence.log")

    File.rm("test/persistence.log")
  end

  test "file doesn't exist" do
    assert {:error, :enoent} = Persistence.load("test/persistence.log")
  end
end
