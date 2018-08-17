defmodule RingLogger.Client.Test do
  use ExUnit.Case, async: false
  alias RingLogger.Client

  describe "configure a client at runtime" do
    setup do
      {:ok, client} = Client.start_link()
      {:ok, %{client: client}}
    end

    test "configure level", %{client: client} do
      Client.configure(client, level: :error)
      assert :error == :sys.get_state(client).level
    end

    test "configure colors", %{client: client} do
      colors = %{
        debug: :red,
        info: :normal,
        warn: :cyan,
        error: :yellow,
        enabled: IO.ANSI.enabled?()
      }

      Client.configure(client, colors: colors)

      assert colors == :sys.get_state(client).colors
    end

    test "configure metadata", %{client: client} do
      Client.configure(client, metadata: %{foo: :bar})
      assert %{foo: :bar} == :sys.get_state(client).metadata
    end

    test "configure io", %{client: client} do
      Client.configure(client, io: :baz)
      assert :baz == :sys.get_state(client).io
    end

    test "configure format", %{client: client} do
      Client.configure(client, format: "Hello")
      assert "Hello" == :sys.get_state(client).format
    end

    test "cannot configure index", %{client: client} do
      Client.configure(client, index: :foo)
      refute :foo == :sys.get_state(client).index
    end
  end
end
