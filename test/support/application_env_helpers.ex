defmodule RingLogger.ApplicationEnvHelpers do
  @moduledoc false

  @doc """
  Set application env for one test, then resets it after

  Add the following tag to set the configuration for `:ring_logger`:

  ```
  @tag application_envs: [ring_logger: [colors: %{debug: :green, error: :blue}]]
  ```
  """
  @spec with_application_env(map(), function()) :: :ok
  def with_application_env(%{application_envs: application_envs} = context, on_exit)
      when is_function(on_exit, 1) do
    if context.async, do: raise("Not compatible with `async: true`")

    for {app, envs} <- application_envs do
      original_envs = Application.get_all_env(app)
      Application.put_all_env([{app, envs}])

      on_exit.(fn ->
        # We need to delete all the existing env because `Application.put_all_env` does a deep merge
        for {key, _val} <- Application.get_all_env(app), do: Application.delete_env(app, key)
        Application.put_all_env([{app, original_envs}])
      end)
    end

    :ok
  end

  def with_application_env(_context, _on_exit), do: :ok
end
