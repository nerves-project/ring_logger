# Changelog

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.10.5

* Fixes
  * Reset potentially outdated indexes when persisted logs are loaded. Fixes
    the case where the persisted logs might have a much higher index than the
    current buffer, so every new log gets added before the loaded logs

## v0.10.4

* Fixes
  * History from loaded persistance file would be reset and lost if multiple
    buffers were configured outside the default buffer when RingLogger was
    reconfigured (at startup or runtime)

## v0.10.3

* Improvements
  * Add ability to grep text of a metadata key (thanks @levex! :heart:).
    See `RingLogger.grep_metadata/2` for more info.

## v0.10.2

* Fixes
  * Fix remaining Elixir 1.15 warnings

## v0.10.1

* Improvements
  * Add guards to prevent some bad API inputs from crashing in places
    disconnected from the original calls.

## v0.10.0

This latest release removes support for Elixir versions before 1.11 to fix
deprecation warnings on Elixir 1.15. Elixir 1.11 to 1.14 are officially
supported and Elixir 1.15 will be supported when released.

* Improvements
  * Support for syncing the RingBuffer to disk at periodic intervals. This
    provides an option between a standard file logger and a fully in-memory log.
    This doesn't provide additional history, but does enable logs to survive
    reboots (assuming they were saved). It's disabled by default. See the
    `:persist_path` and `:persist_seconds` options for details. Thanks to
    @oestrich for adding this feature.

## v0.9.0

This latest release removes support for Elixir versions before 1.9.

* Improvements
  * Support multiple circular buffers and filtering based on log level. This
    makes it possible to separate out debug and info messages so they don't push
    out error messages. See the `README.md` for configuration examples. Thanks
    to @oestrich for this feature.
  * Fixed and added specs throughout

## v0.8.6

* Improvements
  * Fixed crashes when converting unicode chardata. Thanks to @x4lldux for this
    fix.

## v0.8.5

* Improvements
  * `RingLogger.grep/2` supports `:before` and `:after` options
  * Support OTP 25

## v0.8.4

* Fixes
  * Default color enabled option now correctly evaluated at runtime for the active IO

* Improvements
  * `RingLogger.grep` will now highlight matches in the output if color is enabled

## v0.8.3

* Fixes
  * Pull all application environment configuration from `:logger, RingLogger`
    rather than some from there and some from `:ring_logger`. Adding
    configuration under `:ring_logger` is still supported, but prints a
    deprecation warning. Thanks to Jason Axelson for this fix.

## v0.8.2

* Improvements
  * Circular buffer improvements are all upstream in the `circular_buffer`
    library, so this release makes it official by deleting the internal
    implementation and using the hex package.

## v0.8.1

* New features
  * `RingLogger.next/1` now outputs a summary line that says how many log
    messages were recented and how many were filtered. This makes it easier to
    identify when the ring buffer is being overtaken by filtered log entries

* Improvements
  * Several internal refactorings were made to reduce memory usage and
    the number of reductions run in the `RingLogger.Server` GenServer. This
    makes a noticeable improvement when monitoring resource usage on a device.
  * Improved tests to verify more edge conditions

## v0.8.0

* New features
  * Support filtering by OTP application. This uses the same mechanism as
    per-module filtering by automatically adding in all modules that are part of
    an OTP application. It is super useful! See the README.md. Thanks to Jon
    Carstons for adding this feature.
  * Support setting defaults on RingLogger clients so that you can configure
    things like a global default to info level messages and then only show
    debug messages from some applications

## v0.7.0

* New features
  * Added `save/1` to save the current set of log messages in the ring buffer to
    a file

## v0.6.1

* Bug fixes
  * Make `RingLogger.grep` friendlier by supporting strings as arguments

## v0.6.0

Important: `RingLogger.tail` is now `RingLogger.next`. `RingLogger.tail` shows
the last n lines of the log (default is 10).

* New features
  * `grep` greps the whole log entry rather than just the message portion. You
    can `grep` on timestamps and message levels now.
  * Functions that print log messages do the printing in the caller's context so
    that printing timeouts don't happen in RingLogger GenServers calls.
  * Added `:none` as a per-module log level to completely silence a module.
  * Added `:pager` option to specify a custom printer for the interactive
    commands.

## v0.5.0

* New features
  * Add support for changing the log levels on a per-module basis. Thanks to
    Matt Ludwigs for this change. See the README.md for details.
  * Add a `:format` option to accept a custom format function similar to how
    `Logger` supports custom formatting. Thanks to Tim Mecklem for this.
  * Bumped default ring buffer size from 100 messages to 1024.

* Bug fixes
  * Log clients are now fully configurable. Previous versions inadvertantly
    limited the options that could be set.

## v0.4.1

* Bug fixes
  * Fix crash when `grep`'ing iodata
  * Fix `init/1` callback return value when only specifying the module.

## v0.4.0

* New features
  * Added `grep`
  * Automatically add the backend if it's not running when using the IEx helpers

## v0.3.0

Renamed `LoggerCircularBuffer` to `RingLogger` and made backwards incompatible
API changes. Please review docs when upgrading.

* New features
  * Simplified use from IEx by autostarting the Client GenServer
  * Added support for `tail`ing logs

## v0.2.0

Renamed `LoggerCircularBuffer` to `LoggerCircularBuffer`

## v0.1.0

Initial release
