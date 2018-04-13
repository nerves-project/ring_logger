defmodule RingLogger.Configuration.Test do
  use ExUnit.Case, async: true
  alias RingLogger.Configuration, as: Subject

  describe "when there is no log level for the module" do
    setup do
      {:ok, subject: %{_: :info}}
    end

    test "when the log level is exceded", %{subject: subject} do
      assert Subject.meet_level?(subject, TestModule, :warn)
    end

    test "when the log level is not exceded", %{subject: subject} do
      refute Subject.meet_level?(subject, TestModule, :debug)
    end
  end

  describe "where there is no log level set" do
    setup do
      {:ok, subject: %{module_levels: %{}}}
    end

    test "all log levels are meet", %{subject: subject} do
      assert Subject.meet_level?(subject, TestModule, :error)
      assert Subject.meet_level?(subject, TestModule, :warn)
      assert Subject.meet_level?(subject, TestModule, :info)
      assert Subject.meet_level?(subject, TestModule, :debug)
    end
  end

  describe "where the module is set higher than the log level" do
    setup do
      {:ok, subject: %{TestModule => :info, _: :warn}}
    end

    test "when the log level is meet and the module is not", %{subject: subject} do
      assert Subject.meet_level?(subject, TestModule, :warn)
    end

    test "when the log level and the module level are exceded", %{subject: subject} do
      assert Subject.meet_level?(subject, TestModule, :info)
    end

    test "when the log level and the module level are not exceded", %{subject: subject} do
      refute Subject.meet_level?(subject, TestModule, :debug)
    end
  end

  describe "where the module is set lower than the log level" do
    setup do
      {:ok, subject: %{TeestModule => :warn, _: :info}}
    end

    test "when the log level is not meet and the module is", %{subject: subject} do
      assert Subject.meet_level?(subject, TestModule, :warn)
    end

    test "when the log level and the module level are exceded", %{subject: subject} do
      assert Subject.meet_level?(subject, TestModule, :error)
    end

    test "when the log level and the module level are not exceded", %{subject: subject} do
      refute Subject.meet_level?(subject, TestModule, :debug)
    end
  end
end
