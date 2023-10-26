defmodule RingLogger.Viewer do
  @moduledoc """
  A Terminal UI (TUI) based viewer to browse a snapshot of the RingLogger buffer.
  Offers a variety of filtering tools.

  Start the viewer using the following line at the IEx prompt:

  ```
  RingLogger.viewer()
  ```

  Type `help`, `h` or `?` at the log viewer prompt to open a help page.
  Type `exit` or `e` to exit the viewer.
  """

  @headers ["#", "Lvl", "App", "Msg", "Time"]
  @header_lines 2
  @footer_lines 2
  @width_of_layout_items 55
  @min_log_width 30
  @min_log_entries 10

  @min_height @header_lines + @footer_lines + @min_log_entries
  @min_width @width_of_layout_items + @min_log_width

  @init_state %{
    current_screen: :list,
    running: true,
    last_cmd_string: nil,
    current_page: 0,
    screen_dims: %{w: 0, h: 0},
    lowest_log_level: nil,
    before_boot: true,
    grep_filter: nil,
    applications_filter: [],
    raw_logs: []
  }

  @level_strings ["emergency", "alert", "critical", "error", "warning", "notice", "info", "debug"]

  @spec view() :: :ok
  def view() do
    screen_dims = get_screen_dims()

    if screen_dims.w <= @min_width do
      raise "Sorry, your terminal needs to be at least #{@min_width} columns wide to use this tool!"
    end

    if screen_dims.h <= @min_height do
      raise "Sorry, your terminal needs to be at least #{@min_height} rows high to use this tool!"
    end

    IO.puts("Starting RingLogger Viewer...")

    starting_state = @init_state |> get_log_snapshot()

    draw(starting_state)

    :ok
  end

  #### Drawing and IO Functions

  defp draw(state) do
    screen_dims = get_screen_dims()
    new_state = %{state | screen_dims: screen_dims} |> do_draw()

    if new_state.running do
      draw(new_state)
    end
  end

  defp get_screen_dims() do
    {:ok, rows} = :io.rows()
    {:ok, cols} = :io.columns()

    %{w: cols, h: rows}
  end

  defp do_draw(state) do
    reset_screen(state.screen_dims)
    print_header(state.screen_dims)

    filtered_logs =
      state.raw_logs
      |> paginate_logs(state)

    _ =
      Enum.with_index(filtered_logs, fn entry, idx ->
        print_log(state.screen_dims, entry, idx)
      end)

    print_footer(state.screen_dims)

    case IO.gets(compute_prompt(state)) do
      {:error, _} ->
        %{state | running: false}

      :eof ->
        state

      string ->
        string
        |> to_string()
        |> String.trim()
        |> process_command(state, filtered_logs)
    end
  end

  defp compute_prompt(state) do
    per_page = state.screen_dims.h - (@header_lines + @footer_lines)
    prefix = "[#{state.current_page}/#{div(length(state.raw_logs), per_page)}] "

    level_suffix =
      if state.lowest_log_level != nil do
        "(#{Atom.to_string(state.lowest_log_level)})"
      end

    app_suffix =
      if state.applications_filter != [] do
        inspect(state.applications_filter)
      end

    boot_suffix =
      if not state.before_boot do
        "(boot)"
      end

    grep_suffix =
      if state.grep_filter != nil do
        "(#{inspect(state.grep_filter)})"
      end

    "#{prefix}#{boot_suffix}#{grep_suffix}#{level_suffix}#{app_suffix}>"
  end

  defp print_header(screen_dims) do
    log_size = screen_dims.w - @width_of_layout_items

    [
      :io_lib.format(
        "~-3ts | ~-7ts | ~-12ts | ~-#{log_size}ts | ~-20ts~n",
        @headers
      ),
      :binary.copy("-", screen_dims.w)
    ]
    |> IO.write()
  end

  defp print_footer(screen_dims) do
    [
      IO.ANSI.cursor(screen_dims.h, 0),
      IO.ANSI.reset()
    ]
    |> IO.write()
  end

  defp print_log(screen_dims, entry, index) do
    log_size = screen_dims.w - @width_of_layout_items
    {{y, m, d}, {h, min, s, _}} = entry.timestamp
    timestamp = NaiveDateTime.from_erl!({{y, m, d}, {h, min, s}}) |> NaiveDateTime.to_string()

    [
      :io_lib.format(
        "~-3ts | #{get_color(entry.level)}~-7ts#{IO.ANSI.reset()} | ~-12ts | ~-#{log_size}ts | ~-20ts~n",
        [
          to_string(index),
          Atom.to_string(entry.level),
          entry.metadata[:application],
          entry.message |> String.trim() |> String.replace("\n", " "),
          timestamp
        ]
      )
    ]
    |> IO.write()
  end

  defp reset_screen(_screen_dims) do
    [IO.ANSI.clear(), IO.ANSI.cursor(0, 0)] |> IO.write()
  end

  #### Log Filtering / Pagination Functions

  defp get_log_snapshot(state) do
    IO.puts("Fetching and Filtering Logs...")

    entries =
      if state.before_boot do
        RingLogger.get()
      else
        raw = RingLogger.get()

        boot_index =
          Enum.reverse(raw)
          |> Enum.find_index(fn entry ->
            String.contains?(entry.message, "Booting Linux")
          end)

        # Index needs to be negative because we searched from the end of the list
        {_, split_segment} = Enum.split(raw, -boot_index)
        split_segment
      end

    %{state | raw_logs: entries |> apply_log_filters(state)}
  end

  defp paginate_logs(entries, state) do
    per_page = state.screen_dims.h - (@header_lines + @footer_lines)
    current_index = state.current_page * per_page

    Enum.slice(entries, current_index..(current_index + per_page))
  end

  defp apply_log_filters(entries, state) do
    Enum.filter(entries, fn entry ->
      maybe_apply_app_filter?(state, entry) and maybe_apply_level_filter?(state, entry) and
        maybe_apply_grep_filter?(state, entry)
    end)
  end

  defp maybe_apply_app_filter?(%{applications_filter: []}, _entry), do: true

  defp maybe_apply_app_filter?(%{applications_filter: app_list}, entry),
    do: entry.metadata[:application] in app_list

  defp maybe_apply_level_filter?(%{lowest_log_level: nil}, _entry), do: true

  defp maybe_apply_level_filter?(%{lowest_log_level: level}, entry),
    do: Logger.compare_levels(entry.level, level) in [:gt, :eq]

  defp maybe_apply_grep_filter?(%{grep_filter: nil}, _entry), do: true

  defp maybe_apply_grep_filter?(%{grep_filter: expression}, entry),
    do: Regex.match?(expression, entry.message)

  #### Command Handler Functions

  # Use last command string (if there was one) when no cmd given
  defp process_command(nil, state, _current_logs), do: state

  defp process_command("", %{last_cmd_string: last_cmd} = state, current_logs),
    do: process_command(last_cmd, state, current_logs)

  defp process_command(cmd_string, state, current_logs) do
    new_state =
      if Integer.parse(cmd_string) != :error do
        {index, _rest} = Integer.parse(cmd_string)
        _ = inspect_entry(index, state, current_logs)
        state
      else
        first_char = String.at(cmd_string, 0) |> String.downcase()
        command(first_char, cmd_string, state, current_logs)
      end

    %{new_state | last_cmd_string: cmd_string}
  end

  defp command(cmd_exit, _cmd_string, state, _current_logs) when cmd_exit in ["e", "q"] do
    %{state | running: false}
  end

  defp command(help_cmd, _cmd_string, state, _current_logs) when help_cmd in ["h", "?"] do
    _ = show_help(state)
    state
  end

  defp command("n", _cmd_string, state, _current_logs) do
    next_page(state)
  end

  defp command("p", _cmd_string, state, _current_logs) do
    prev_page(state)
  end

  defp command("j", cmd_string, state, _current_logs) do
    jump_to_page(cmd_string, state)
  end

  defp command("r", _cmd_string, _state, _current_logs) do
    @init_state |> get_log_snapshot()
  end

  defp command("b", _cmd_string, state, _current_logs) do
    %{state | before_boot: !state.before_boot} |> get_log_snapshot()
  end

  defp command("l", cmd_string, state, _current_logs) do
    set_log_level(cmd_string, state) |> get_log_snapshot()
  end

  defp command("a", cmd_string, state, _current_logs) do
    add_remove_app(cmd_string, state) |> get_log_snapshot()
  end

  defp command("g", cmd_string, state, _current_logs) do
    add_remove_grep(cmd_string, state) |> get_log_snapshot()
  end

  defp command(_, _cmd_string, state, _current_logs), do: state

  defp next_page(%{current_page: n} = state), do: %{state | current_page: n + 1}
  defp prev_page(%{current_page: 0} = state), do: %{state | current_page: 0}
  defp prev_page(%{current_page: n} = state), do: %{state | current_page: n - 1}

  defp jump_to_page(cmd_string, state) do
    split = String.split(cmd_string)

    case length(split) do
      1 ->
        per_page = state.screen_dims.h - (@header_lines + @footer_lines)
        last_page = div(length(state.raw_logs), per_page)
        %{state | current_page: last_page}

      2 ->
        {page, _} = Integer.parse(Enum.at(split, 1))
        %{state | current_page: max(0, page)}

      _ ->
        state
    end
  rescue
    _ -> state
  end

  defp inspect_entry(index, state, current_logs) do
    if index <= length(current_logs) do
      selected = Enum.at(current_logs, index)
      reset_screen(state.screen_dims)

      IO.puts([
        "\n----------Log Inspect----------\n",
        "\n#{inspect(selected[:metadata], pretty: true)}\n",
        "\n----------\n",
        get_color(selected.level),
        selected.message,
        IO.ANSI.reset(),
        "\n----------\n"
      ])

      _ = IO.gets("Press Enter To Close...")
    end
  end

  defp set_log_level(cmd_string, state) do
    split = String.split(cmd_string)

    cond do
      length(split) <= 1 ->
        # No args, clear the log level filter
        %{state | lowest_log_level: nil}

      length(split) == 2 and Enum.at(split, 1) in @level_strings ->
        # 2 args, 2nd arg is a valid log level string
        level_str = Enum.at(split, 1)
        level_atom = String.to_existing_atom(level_str)
        %{state | lowest_log_level: level_atom}

      true ->
        state
    end
  end

  defp add_remove_app(cmd_string, state) do
    split = String.split(cmd_string)

    cond do
      length(split) == 1 ->
        %{state | applications_filter: []}

      length(split) == 2 ->
        app_atom = String.to_existing_atom(Enum.at(split, 1))

        if app_atom in state.applications_filter do
          %{state | applications_filter: List.delete(state.applications_filter, app_atom)}
        else
          %{state | applications_filter: [app_atom | state.applications_filter]}
        end

      true ->
        state
    end
  rescue
    _ -> state
  end

  defp add_remove_grep(cmd_string, state) do
    [_, str] = String.split(cmd_string, " ", parts: 2, trim: true)

    case Regex.compile(str) do
      {:ok, expression} ->
        %{state | grep_filter: expression}

      _ ->
        state
    end
  rescue
    # We can't force String.split/2 with parts = 2 to not raise if they only provide 1 arg
    # So treat this as the reset condition
    _ -> %{state | grep_filter: nil}
  end

  defp show_help(state) do
    reset_screen(state.screen_dims)

    IO.puts([
      "\n----------Log Viewer Help----------\n",
      "Commands:\n",
      "\t(n)ext - navigate to the next page of the log buffer.\n",
      "\t(p)rev - navigate to the previous page of the log buffer.\n",
      "\t(j)ump [number] - jump to a page number. leaving number off jumps to the last page.\n",
      "\t(r)eset - reset the log viewer, clears all filters and resets the current page.\n",
      "\t(b)oot - toggles a 'since most recent boot' filter.\n",
      "\t(g)rep [regex/string] - regex/string search expression, leaving argument blank clears filter.\n",
      "\t(l)evel [log_level] - filter to specified level (or higher), leaving level blank clears the filter.\n",
      "\t(a)pp [atom] - adds/remove an atom from the 'application' metadata filter, leaving argument blank clears filter.\n",
      "\t0..n - input any table index number to fully inspect a log line, and view its metadata.\n",
      "\t(e)xit or (q)uit - closes the log viewer.\n",
      "\t(h)elp / ? - show this screen.\n",
      "\n----------\n"
    ])

    _ = IO.gets("Press Enter To Close...")
  end

  #### Misc Util Functions

  defp get_color(:emergency), do: IO.ANSI.white() <> IO.ANSI.red_background()
  defp get_color(:alert), do: IO.ANSI.white() <> IO.ANSI.red_background()
  defp get_color(:critical), do: IO.ANSI.white() <> IO.ANSI.red_background()
  defp get_color(:error), do: IO.ANSI.red()
  defp get_color(:warn), do: IO.ANSI.yellow()
  defp get_color(:warning), do: IO.ANSI.yellow()
  defp get_color(:notice), do: IO.ANSI.light_blue()
  defp get_color(:info), do: IO.ANSI.light_blue()
  defp get_color(:debug), do: IO.ANSI.cyan()
  defp get_color(_), do: IO.ANSI.white()
end
