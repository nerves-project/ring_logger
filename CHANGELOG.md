# Changelog

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
