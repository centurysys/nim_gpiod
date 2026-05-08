# nim_gpiod

`nim_gpiod` is a small Linux GPIO library for Nim.

It provides a simple API for reading GPIO inputs and waiting for edge events.
The public API is kept close to the original `nim_gpiod` interface, but the
implementation no longer depends on `libgpiod`.

Instead, this version uses the Linux GPIO character device v2 ABI directly
through a small bundled C shim.

## Why this exists

`libgpiod` v1 and v2 use significantly different C APIs. This caused practical
problems when the same Nim application needed to build on distributions that
ship different `libgpiod` versions.

`nim_gpiod` avoids that split by using the kernel GPIO character device v2 API
directly.

As long as the target kernel provides GPIO chardev v2, applications do not need
to care whether the distribution ships `libgpiod` v1, `libgpiod` v2, or no
`libgpiod` package at all.

## Features

- Open a GPIO line by line name
- Open a GPIO line by chip path and offset
- Read input values
- Wait for rising, falling, or both edge events
- Optional active-low handling
- Event metadata support:
  - timestamp in nanoseconds
  - global sequence number
  - line sequence number
- Result-based APIs for explicit error handling
- Exception-based compatibility APIs
- No runtime dependency on `libgpiod`
- No Futhark/libclang requirement for normal builds

## Requirements

- Linux kernel with GPIO character device v2 support
- Usable `/dev/gpiochipN` devices
- C compiler available during Nim build
- Nim
- `results` Nim package

The implementation is intended for modern embedded Linux systems. The current
target environments are Linux 5.10.y or newer.

## Project layout

```text
src/
  nim_gpiod.nim
  nim_gpiod/
    async_gpio.nim
    errors.nim
    types.nim
    bindings/
      c_api.nim
      generated/
        ngpio.nim
    shim/
      ngpio.h
      ngpio.c
tests/
  test_poll_watch.nim
  test_event_watch.nim
```

The C shim is compiled into the Nim application with Nim's `{.compile.}` pragma.
The generated-style Nim binding is committed to the repository, so normal users
do not need Futhark or libclang.

## Basic usage

```nim
import nim_gpiod

let gpio = newGpio("SIM2_CD", "my_app")
echo gpio.getValue()
gpio.close()
```

`newGpio()` raises `OSError` on failure. For explicit error handling, use
`openGpio()` and `getValueRes()`.

```nim
import nim_gpiod

let gpioRes = openGpio("SIM2_CD", "my_app")
if gpioRes.isErr:
  echo gpioRes.error
  quit 1

let gpio = gpioRes.value
defer:
  gpio.close()

let valueRes = gpio.getValueRes()
if valueRes.isErr:
  echo valueRes.error
  quit 1

echo valueRes.value
```

## Waiting for edge events

```nim
import std/asyncdispatch

import nim_gpiod

proc main() {.async.} =
  let gpio = newGpio("DI0", "my_app")
  defer:
    gpio.close()

  let edge = await gpio.waitEvent(Edge.Both)
  echo edge

waitFor main()
```

`waitEvent()` returns only the detected edge for compatibility.

Use `waitEventInfo()` or `waitEventRes()` if timestamp and sequence numbers are
needed.

```nim
let ev = await gpio.waitEventInfo(Edge.Both)
echo ev.edge
echo ev.timestampNs
echo ev.seqno
echo ev.lineSeqno
```

## Active-low

Some input signals are logically active-low. Pass `activeLow = true` when
opening the line.

```nim
let gpio = newGpio("DI0", "my_app", activeLow = true)
```

The goal is for the Nim API to expose logical values instead of raw electrical
levels.

## Polling test

Some GPIO providers, especially I2C GPIO expanders without interrupt wiring,
can be read as inputs but cannot be used for edge events.

For those lines, use the polling test.

```sh
nim c -d:release --cpu:arm64 tests/test_poll_watch.nim
./tests/test_poll_watch SIM2_CD 100
```

Example output:

```text
line       : SIM2_CD
intervalMs : 100
activeLow  : false
2026-05-08 19:27:54.272 value=0 initial
2026-05-08 19:28:24.513 value=1 changed from 0
2026-05-08 19:28:25.819 value=0 changed from 1
```

## Edge event test

For GPIO lines that support edge events:

```sh
nim c -d:release --cpu:arm64 tests/test_event_watch.nim
./tests/test_event_watch DI0 both
```

If the line is readable but edge requests fail with `No such device or address`,
the GPIO provider probably does not support interrupts for that line, or the
interrupt line is not described in the board configuration.

## Public API overview

### Types

```nim
type
  Edge {.pure.} = enum
    Falling
    Rising
    Both

  EventEdge {.pure.} = enum
    Falling
    Rising

  Event = object
    edge: EventEdge
    timestampNs: uint64
    seqno: uint32
    lineSeqno: uint32
```

### Open

```nim
proc openGpio(
  lineName: string,
  consumer = "nim_gpiod",
  activeLow = false
): GE[AsyncGpio]

proc openGpioByChipOffset(
  chipPath: string,
  offset: uint,
  consumer = "nim_gpiod",
  activeLow = false
): GE[AsyncGpio]
```

### Compatibility constructors

```nim
proc newGpio(
  lineName: string,
  consumer = "nim_gpiod",
  activeLow = false
): AsyncGpio

proc newGpioByChipOffset(
  chipPath: string,
  offset: uint,
  consumer = "nim_gpiod",
  activeLow = false
): AsyncGpio
```

### Read

```nim
proc getValueRes(self: AsyncGpio): GE[int]
proc getValue(self: AsyncGpio): int
```

### Edge events

```nim
proc waitEventRes(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[GE[Event]]

proc waitEventInfo(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Event]

proc waitEvent(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Edge]
```

### Close

```nim
proc close(self: AsyncGpio)
proc isOpen(self: AsyncGpio): bool
```

## Notes

This library intentionally focuses on industrial-style digital inputs and simple
edge monitoring.

It does not currently expose pull-up/down bias, drive mode, open-drain,
open-source, or multi-line request APIs. Those settings are usually board-level
hardware design concerns in the intended use cases.

## License

MIT
