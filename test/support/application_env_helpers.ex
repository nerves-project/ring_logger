defmodule RingLogger.ApplicationEnvHelpers do
  @doc """
  Set application env for one test, then resets it after

  Add the following tag to set the configuration for `:ring_logger`:

  ```
  @tag application_envs: [ring_logger: [colors: %{debug: :green, error: :blue}]]
  ```
  """
  def with_application_env(%{application_envs: application_envs} = context, on_exit)
      when is_function(on_exit, 1) do
    if context.async, do: raise("Not compatible with `async: true`")

    for {app, envs} <- application_envs do
      original_envs = Application.get_all_env(app)
      put_all_env([{app, envs}])

      on_exit.(fn ->
        # We need to delete all the existing env because `Application.put_all_env` does a deep merge
        for {key, _val} <- Application.get_all_env(app), do: Application.delete_env(app, key)
        put_all_env([{app, original_envs}])
      end)
    end
  end

  def with_application_env(_context, _on_exit), do: :ok

  # `Application.put_all_env/2` is not availble until Elixir 1.9
  defp put_all_env(application_envs) do
    for {app, envs} <- application_envs,
        {key, val} <- envs do
      Application.put_env(app, key, val)
    end
  end
end
