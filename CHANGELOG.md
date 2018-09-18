# Changelog

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
