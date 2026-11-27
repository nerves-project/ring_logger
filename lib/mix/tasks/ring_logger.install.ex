# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.RingLogger.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Installs RingLogger as a Logger backend in your project."
  end

  @spec example() :: String.t()
  def example() do
    "mix igniter.install ring_logger"
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    This sets a project up the same way as `mix nerves.new` does:

    * `:logger_backends` is added to the dependencies in `mix.exs`
    * `RingLogger` is added as a logger backend in `config/runtime.exs`
    * In Nerves projects, Elixir's default console log handler is turned off
      for the device in `config/target.exs` so that log messages only go to
      `RingLogger` there. On your computer, and in other projects, log
      messages still go to the console as well.

    Existing logger configuration is kept. Projects that already list
    `RingLogger` under `config :logger, backends: [...]` are left alone.

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.RingLogger.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Function
    alias Igniter.Project.Config
    alias Igniter.Project.Deps
    alias Sourceror.Zipper

    @logger_backends_dep {:logger_backends, "~> 1.0"}
    @runtime_config "config/runtime.exs"
    @add_backend_code """
    Application.ensure_all_started(:logger_backends)
    LoggerBackends.add(RingLogger)
    """
    @legacy_config_files ["config/config.exs", "config/target.exs", "config/host.exs"]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :ring_logger,
        # Fetched by `mix igniter.install` before this task runs
        adds_deps: new_logger_backends_dep(),
        installs: [],
        # An example invocation
        example: __MODULE__.Docs.example(),
        # A list of environments that this should be installed in.
        only: nil,
        # a list of positional arguments, i.e `[:file]`
        positional: [],
        # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
        # This ensures your option schema includes options from nested tasks
        composes: [],
        # `OptionParser` schema
        schema: [],
        # Default values for the options in the `schema`
        defaults: [],
        # CLI aliases
        aliases: [],
        # A list of options in the schema that are required
        required: []
      }
    end

    # Igniter replaces a dependency that's already in the mix.exs with the one
    # from `adds_deps` when their declarations differ. Projects that already
    # depend on `:logger_backends` keep their declaration.
    defp new_logger_backends_dep() do
      existing =
        for dep <- List.wrap(Mix.Project.config()[:deps]), is_tuple(dep), do: elem(dep, 0)

      if :logger_backends in existing, do: [], else: [@logger_backends_dep]
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      case Enum.filter(@legacy_config_files, &legacy_backend?(igniter, &1)) do
        [] ->
          igniter
          |> add_logger_backends_dep()
          |> add_backend_to_runtime_config()
          |> disable_default_handler()

        files ->
          Igniter.add_notice(igniter, """
          ring_logger: RingLogger is already listed under `config :logger, backends: [...]`
          in #{Enum.join(files, ", ")}, so nothing was changed.

          Elixir has deprecated the `:backends` key. To get rid of the warning
          at startup, remove RingLogger from that list and rerun this installer.
          """)
      end
    end

    # `adds_deps` only takes effect when this task is run by `mix
    # igniter.install` or is listed in another installer's `composes`. Adding
    # the dependency here as well covers running `mix ring_logger.install`
    # directly and a plain `Igniter.compose_task/3`. It isn't fetched in those
    # cases. Mix tells the user to run `mix deps.get`.
    defp add_logger_backends_dep(igniter) do
      Deps.add_dep(igniter, @logger_backends_dep, on_exists: :skip)
    end

    defp add_backend_to_runtime_config(igniter) do
      Igniter.create_or_update_elixir_file(
        igniter,
        @runtime_config,
        "import Config\n\n" <> @add_backend_code,
        &add_backend/1
      )
    end

    defp add_backend(zipper) do
      root = Zipper.topmost_root(zipper)

      if any_node?(root, &add_ring_logger_call?/1) do
        {:ok, zipper}
      else
        {:ok, do_add_backend(Common.maybe_move_to_block(zipper))}
      end
    end

    # `LoggerBackends.add/1` needs the `:logger_backends` application, so it
    # goes below a top-level call that starts it when there is one. Otherwise
    # both lines go right below `import Config` so that the backend is added
    # no matter what the rest of the file does.
    defp do_add_backend(zipper) do
      both = @add_backend_code
      add = "LoggerBackends.add(RingLogger)"

      with :error <- move_to_ensure_started(zipper),
           :error <- Function.move_to_function_call_in_current_scope(zipper, :import, 1) do
        Common.add_code(zipper, both, placement: :before)
      else
        {:ok, %{node: node} = found} ->
          code = if ensure_started_call?(node), do: add, else: both
          Common.add_code(found, code, placement: :after)
      end
    end

    defp move_to_ensure_started(zipper) do
      Common.move_right(zipper, &ensure_started_call?(&1.node))
    end

    defp ensure_started_call?(
           {{:., _, [{:__aliases__, _, [:Application]}, :ensure_all_started]}, _, [arg | _]}
         ) do
      unwrap(arg) == :logger_backends
    end

    defp ensure_started_call?(_node), do: false

    defp add_ring_logger_call?({{:., _, [{:__aliases__, _, [:LoggerBackends]}, :add]}, _, args}) do
      mentions_ring_logger?(args)
    end

    defp add_ring_logger_call?(_node), do: false

    # The console logger is only turned off for the device. Doing it in
    # config.exs would also silence `mix test` and `iex -S mix` on the host.
    defp disable_default_handler(igniter) do
      if Igniter.exists?(igniter, "config/target.exs") do
        Config.configure_new(igniter, "target.exs", :logger, [:default_handler], false)
      else
        Igniter.add_notice(igniter, """
        ring_logger: config/target.exs was not found, so the console logger
        was left on and log messages go to both it and RingLogger.

        Nerves projects normally turn it off on the device with:

            config :logger, :default_handler, false
        """)
      end
    end

    # True if RingLogger is in `config :logger, backends: [...]` or
    # `config :logger, :backends, [...]` in the given config file.
    defp legacy_backend?(igniter, path) do
      with true <- Igniter.exists?(igniter, path),
           {:ok, quoted} <- igniter |> read_content(path) |> Sourceror.parse_string() do
        any_node?(quoted, &legacy_backend_config?/1)
      else
        _ -> false
      end
    end

    defp legacy_backend_config?({:config, _, [app, key, value]}) do
      unwrap(app) == :logger and unwrap(key) == :backends and mentions_ring_logger?(value)
    end

    defp legacy_backend_config?({:config, _, [app, opts]}) when is_list(opts) do
      unwrap(app) == :logger and
        Enum.any?(opts, fn
          {key, value} -> unwrap(key) == :backends and mentions_ring_logger?(value)
          _ -> false
        end)
    end

    defp legacy_backend_config?(_node), do: false

    defp read_content(igniter, path) do
      igniter
      |> Igniter.include_existing_file(path)
      |> Map.fetch!(:rewrite)
      |> Rewrite.source!(path)
      |> Rewrite.Source.get(:content)
    end

    defp mentions_ring_logger?(quoted) do
      any_node?(quoted, &match?({:__aliases__, _, [:RingLogger]}, &1))
    end

    defp any_node?(quoted, fun) do
      {_quoted, found?} = Macro.prewalk(quoted, false, &{&1, &2 or fun.(&1)})
      found?
    end

    # Sourceror wraps literals in `:__block__` nodes to hold their metadata
    defp unwrap({:__block__, _, [value]}), do: value
    defp unwrap(value), do: value
  end
else
  defmodule Mix.Tasks.RingLogger.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ring_logger.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
