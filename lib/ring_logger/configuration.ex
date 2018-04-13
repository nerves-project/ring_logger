defmodule RingLogger.Configuration do

  def meet_level?(module_levels, module, level) when is_map(module_levels) do
    default_level = module_levels
                    |> Map.get(:_, :debug)
    module_levels
    |> Map.get(module, default_level)
    |> do_meet_level?(level)
  end

  def meet_level?(nil,_,_) do
    # Not using module levels
    true
  end

  defp do_meet_level?(nil, _level), do: true

  defp do_meet_level?(minimum_level, level) do
    Logger.compare_levels(level, minimum_level) != :lt
  end
end
