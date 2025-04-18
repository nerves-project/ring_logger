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

  @headers ["#", "Level", "Application", "Message", "Timestamp"]
  @header_lines 2
  @footer_lines 1
  @width_of_layout_items 53
  @min_log_width 25
  @min_log_entries 10

  @min_height @header_lines + @footer_lines + @min_log_entries
  @min_width @width_of_layout_items + @min_log_width

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
    timestamp_filter: [],
    raw_logs: []
  }

  @level_strings ["emergency", "alert", "critical", "error", "warning", "notice", "info", "debug"]

  @microsecond_factor 1_000_000

  @seconds_in_year 365 * 24 * 60 * 60
  @seconds_in_month 30 * 24 * 60 * 60
  @seconds_in_week 7 * 24 * 60 * 60
  @seconds_in_day 24 * 60 * 60
  @seconds_in_hour 60 * 60
  @seconds_in_minute 60

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

    @init_state |> get_log_snapshot() |> loop()
  end

  @doc """
  updates state by applying multiple filters to initial state or return initial state
  """
  def parse_launch_cmd("", state), do: state

  @spec parse_launch_cmd(String.t(), map()) :: map()
  def parse_launch_cmd(cmd_string, state) do
    cmd_list = String.split(cmd_string, ";")

    state =
      Enum.reduce(cmd_list, state, fn cmd, state ->
        cmd_char = String.trim_leading(cmd, " ") |> String.at(0) |> String.downcase()
        apply_command_parser(cmd_char, cmd, state)
      end)

    %{state | current_page: 0}
  end

  # apply_command_parser/3 returns state by applying single filter
  defp apply_command_parser(cmd_char, cmd, state) do
    case {cmd_char, cmd, state} do
      {"d", cmd, state} -> add_time_log(cmd, state)
      _ -> state
    end
  end

  #### Drawing and IO Functions
  defp loop(%{running: false} = _state) do
    :ok
  end

  defp loop(state) do
    screen_dims = get_screen_dims()

    state |> update_dimensions(screen_dims) |> do_draw() |> loop()
  end

  defp get_screen_dims() do
    {:ok, rows} = :io.rows()
    {:ok, cols} = :io.columns()

    %{w: cols, h: rows}
  end

  defp update_dimensions(%{screen_dims: screen_dims} = state, screen_dims) do
    # No changes
    state
  end

  defp update_dimensions(state, screen_dims) do
    %{state | screen_dims: screen_dims} |> recalculate_pagination()
  end

  defp recalculate_pagination(state) do
    index = state.per_page * state.current_page

    per_page = state.screen_dims.h - (@header_lines + @footer_lines)
    page_count = ceil(length(state.raw_logs) / per_page)
    last_page = page_count - 1

    current_page = div(index, per_page)

    %{
      state
      | per_page: per_page,
        current_page: current_page,
        last_page: last_page
    }
  end

  defp do_draw(state) do
    filtered_logs = current_page(state)

    [
      reset_screen(),
      header(state.screen_dims),
      Enum.with_index(filtered_logs, fn entry, idx ->
        format_log(state.screen_dims, entry, idx)
      end),
      footer(state.screen_dims)
    ]
    |> IO.write()

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
    prefix = "[#{state.current_page}/#{state.last_page}] "

    timestamp_suffix =
      if state.timestamp_filter != [] do
        {:ok, dt} =
          DateTime.from_unix(div(state.timestamp_filter[:start_time], @microsecond_factor))

        "@#{dt}"
      end

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

    "#{prefix}#{boot_suffix}#{grep_suffix}#{level_suffix}#{app_suffix}#{timestamp_suffix}>"
  end

  defp header(screen_dims) do
    log_size = screen_dims.w - @width_of_layout_items

    [
      :io_lib.format(
        "~-3ts | ~-5ts | ~-12ts | ~-#{log_size}ts | ~-20ts~n",
        @headers
      ),
      :binary.copy("-", screen_dims.w)
    ]
  end

  defp footer(screen_dims) do
    [
      IO.ANSI.cursor(screen_dims.h, 0),
      IO.ANSI.reset()
    ]
  end

  defp format_log(screen_dims, entry, index) do
    log_size = screen_dims.w - @width_of_layout_items
    {{y, m, d}, {h, min, s, _}} = entry.timestamp
    timestamp = NaiveDateTime.from_erl!({{y, m, d}, {h, min, s}}) |> NaiveDateTime.to_string()

    [
      :io_lib.format(
        "~-3ts | ~ts#{IO.ANSI.reset()} | ~-12ts | ~-#{log_size}ts | ~-20ts~n",
        [
          to_string(index),
          format_level(entry.level),
          entry.metadata[:application],
          entry.message |> String.trim() |> String.replace("\n", " "),
          timestamp
        ]
      )
    ]
  end

  defp reset_screen() do
    [IO.ANSI.clear(), IO.ANSI.cursor(0, 0)]
  end

  #### Log Filtering / Pagination Functions

  defp get_log_snapshot(state) do
    IO.puts("Fetching and Filtering Logs...")

    entries =
      if state.before_boot do
        RingLogger.get()
      else
        raw = RingLogger.get()

        boot_index = find_starting_index(raw)

        # Index needs to be negative because we searched from the end of the list
        {_, split_segment} = Enum.split(raw, -boot_index)
        split_segment
      end

    %{state | raw_logs: entries |> apply_log_filters(state)} |> recalculate_pagination()
  end

  defp find_starting_index(entries) do
    index =
      Enum.reverse(entries)
      |> Enum.find_index(fn entry ->
        String.contains?(entry.message, "Linux version ")
      end)

    if index do
      index + 1
    else
      0
    end
  end

  defp current_page(state) do
    page_first_index = state.current_page * state.per_page
    page_last_index = page_first_index + state.per_page - 1

    Enum.slice(state.raw_logs, page_first_index..page_last_index)
  end

  defp apply_log_filters(entries, state) do
    Enum.filter(entries, fn entry ->
      maybe_apply_app_filter?(state, entry) and maybe_apply_level_filter?(state, entry) and
        maybe_apply_grep_filter?(state, entry) and maybe_apply_timestamp_filter?(state, entry)
    end)
  end

  defp maybe_apply_timestamp_filter?(%{timestamp_filter: []}, _entry), do: true

  defp maybe_apply_timestamp_filter?(
         %{timestamp_filter: [start_time: start_time, end_time: 0]},
         entry
       ),
       do: check_start_timestamp(start_time, entry)

  defp maybe_apply_timestamp_filter?(state, entry), do: check_date_range(state, entry)

  defp check_start_timestamp(start_time, entry) do
    entry.metadata[:time] >= start_time
  end

  defp check_date_range(state, entry) do
    entry.metadata[:time] >= state.timestamp_filter[:start_time] &&
      entry.metadata[:time] <= state.timestamp_filter[:end_time]
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
        inspect_entry(index, state, current_logs)
        state
      else
        first_char = String.at(cmd_string, 0) |> String.downcase()
        command(first_char, cmd_string, state)
      end

    %{new_state | last_cmd_string: cmd_string}
  end

  defp command(cmd_exit, _cmd_string, state) when cmd_exit in ["e", "q"] do
    %{state | running: false}
  end

  defp command(help_cmd, _cmd_string, state) when help_cmd in ["h", "?"] do
    show_help(state)
  end

  defp command("n", _cmd_string, state) do
    next_page(state)
  end

  defp command("p", _cmd_string, state) do
    prev_page(state)
  end

  defp command("j", cmd_string, state) do
    jump_to_page(cmd_string, state)
  end

  defp command("r", _cmd_string, _state) do
    @init_state |> get_log_snapshot()
  end

  defp command("b", _cmd_string, state) do
    %{state | before_boot: !state.before_boot, current_page: 0} |> get_log_snapshot()
  end

  defp command("l", cmd_string, state) do
    set_log_level(cmd_string, state) |> get_log_snapshot()
  end

  defp command("a", cmd_string, state) do
    add_remove_app(cmd_string, state) |> get_log_snapshot()
  end

  defp command("d", cmd_string, state) do
    add_time_log(cmd_string, state) |> get_log_snapshot()
  end

  defp command("g", cmd_string, state) do
    add_remove_grep(cmd_string, state) |> get_log_snapshot()
  end

  defp command(_, _cmd_string, state), do: state

  defp next_page(%{current_page: p, last_page: p} = state), do: state
  defp next_page(%{current_page: n} = state), do: %{state | current_page: n + 1}
  defp prev_page(%{current_page: 0} = state), do: state
  defp prev_page(%{current_page: n} = state), do: %{state | current_page: n - 1}

  defp jump_to_page(cmd_string, state) do
    case String.split(cmd_string) do
      [_] ->
        %{state | current_page: state.last_page}

      [_, page_string] ->
        {page, _} = Integer.parse(page_string)
        %{state | current_page: min(max(0, page), state.last_page)}

      _ ->
        state
    end
  rescue
    _ -> state
  end

  defp inspect_entry(index, _state, current_logs) do
    if index <= length(current_logs) do
      selected = Enum.at(current_logs, index)

      IO.puts([
        reset_screen(),
        "\n----------Log Inspect----------\n",
        "\n#{inspect(selected[:metadata], pretty: true)}\n",
        "\n----------\n",
        selected.message,
        "\n----------\n"
      ])

      _ = IO.gets("Press enter to close...")
      :ok
    end
  end

  defp set_log_level(cmd_string, state) do
    case {String.split(cmd_string), state.lowest_log_level} do
      {[_cmd], previous} when previous != nil ->
        # No args, clear the log level filter
        %{state | lowest_log_level: nil, current_page: 0}

      {[_cmd, new_level], level} when new_level != level and new_level in @level_strings ->
        # 2 args, 2nd arg is a valid log level string
        level_atom = String.to_existing_atom(new_level)
        %{state | lowest_log_level: level_atom, current_page: 0}

      _ ->
        state
    end
  end

  defp add_time_log(cmd_string, state) do
    case split_input(cmd_string) do
      {datetime_str, duration_str} ->
        dt_start_micro_secs =
          convert_to_secs(String.trim_trailing(datetime_str)) * @microsecond_factor

        dt_end_micro_secs =
          parse_duration_string(duration_str, datetime_str) * @microsecond_factor

        %{
          state
          | timestamp_filter: [start_time: dt_start_micro_secs, end_time: dt_end_micro_secs],
            current_page: 0
        }
    end
  rescue
    _ -> %{state | timestamp_filter: [], current_page: 0}
  end

  defp parse_duration_string(nil, _datetime), do: 0

  defp parse_duration_string(duration_string, datetime_string) do
    with {:module, duration} <- Code.ensure_loaded(Duration),
         {:ok, duration} <- duration.from_iso8601(duration_string) do
      convert_to_secs(String.trim_trailing(datetime_string)) +
        duration.year * @seconds_in_year +
        duration.month * @seconds_in_month +
        duration.week * @seconds_in_week +
        duration.day * @seconds_in_day +
        duration.hour * @seconds_in_hour +
        duration.minute * @seconds_in_minute +
        duration.second
    else
      _ -> 0
    end
  end

  defp split_input(input) do
    case String.split(input, ~r/(d\s|(?=P))/, parts: 3) do
      [_cmd, datetime_str, duration_str] -> {datetime_str, duration_str}
      [_cmd, datetime_str] -> {datetime_str, nil}
    end
  end

  defp convert_to_secs(time_str) do
    case Date.from_iso8601(time_str) do
      {:ok, _dt} ->
        {:ok, dt, _offset} = DateTime.from_iso8601(time_str <> "T00:00:00Z")
        DateTime.to_unix(dt)

      {:error, _reason} ->
        try_naive_date_parsing(time_str)
    end
  end

  defp try_naive_date_parsing(time_str) do
    case NaiveDateTime.from_iso8601(time_str) do
      {:ok, naive_dt} ->
        {:ok, dt} = DateTime.from_naive(naive_dt, "Etc/UTC")
        DateTime.to_unix(dt)

      {:error, _reason} ->
        0
    end
  end

  defp add_remove_app(cmd_string, state) do
    case String.split(cmd_string) do
      [_cmd] ->
        %{state | applications_filter: [], current_page: 0}

      [_cmd, app_str] ->
        app_atom = String.to_existing_atom(app_str)

        if app_atom in state.applications_filter do
          %{
            state
            | applications_filter: List.delete(state.applications_filter, app_atom),
              current_page: 0
          }
        else
          %{state | applications_filter: [app_atom | state.applications_filter], current_page: 0}
        end

      _ ->
        state
    end
  rescue
    _ -> state
  end

  defp add_remove_grep(cmd_string, state) do
    [_, str] = String.split(cmd_string, " ", parts: 2, trim: true)

    case Regex.compile(str) do
      {:ok, expression} ->
        %{state | grep_filter: expression, current_page: 0}

      _ ->
        state
    end
  rescue
    # We can't force String.split/2 with parts = 2 to not raise if they only provide 1 arg
    # So treat this as the reset condition
    _ -> %{state | grep_filter: nil, current_page: 0}
  end

  defp show_help(state) do
    IO.puts([
      reset_screen(),
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
      "\t(d)ate [start_time] [duration] - show entries at specified time and duration. [ex. d 2024-12-25 10:20:01 P0Y0M0W0DT0H1M0S]\n",
      "\t0..n - input any table index number to fully inspect a log line, and view its metadata.\n",
      "\t(e)xit or (q)uit - closes the log viewer.\n",
      "\t(h)elp / ? - show this screen.\n",
      "\n----------\n"
    ])

    _ = IO.gets("Press enter to close...")
    state
  end

  #### Misc Util Functions

  defp format_level(:emergency), do: [IO.ANSI.white(), IO.ANSI.red_background(), "emerg"]
  defp format_level(:alert), do: [IO.ANSI.white(), IO.ANSI.red_background(), "alert"]
  defp format_level(:critical), do: [IO.ANSI.white(), IO.ANSI.red_background(), "crit "]
  defp format_level(:error), do: [IO.ANSI.red(), "error"]
  defp format_level(:warn), do: [IO.ANSI.yellow(), "warn "]
  defp format_level(:warning), do: [IO.ANSI.yellow(), "warn "]
  defp format_level(:notice), do: [IO.ANSI.light_blue(), "notic"]
  defp format_level(:info), do: [IO.ANSI.light_blue(), "info "]
  defp format_level(:debug), do: [IO.ANSI.cyan(), "debug"]
  defp format_level(_), do: [IO.ANSI.white(), "?    "]
end
