import std/asyncdispatch
import std/os
import std/strformat
import std/strutils
import std/times

import nim_gpiod

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc usage() =
  let app = getAppFilename().extractFilename()
  echo &"Usage: {app} [line-name] [interval-ms] [active-low]"
  echo ""
  echo "Arguments:"
  echo "  line-name    GPIO line name. Default: SIM_CD"
  echo "  interval-ms  Poll interval in milliseconds. Default: 100"
  echo "  active-low   true | false | 1 | 0. Default: false"
  echo ""
  echo "Examples:"
  echo &"  {app}"
  echo &"  {app} SIM_CD"
  echo &"  {app} SIM2_CD 100"
  echo &"  {app} SIM2_CD 50 true"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc parseBoolArg(s: string): bool =
  case s
  of "1", "true", "True", "yes", "Yes", "on", "On":
    result = true
  of "0", "false", "False", "no", "No", "off", "Off":
    result = false
  else:
    raise newException(ValueError, &"invalid bool value: {s}")

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc nowText(): string =
  result = now().format("yyyy-MM-dd HH:mm:ss'.'fff")

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc main() {.async.} =
  if paramCount() >= 1:
    let a = paramStr(1)
    if a == "-h" or a == "--help":
      usage()
      return

  let lineName =
    if paramCount() >= 1: paramStr(1)
    else: "SIM_CD"

  let intervalMs =
    if paramCount() >= 2: parseInt(paramStr(2))
    else: 100

  let activeLow =
    if paramCount() >= 3: parseBoolArg(paramStr(3))
    else: false

  if intervalMs <= 0:
    raise newException(ValueError, "interval-ms must be greater than 0")

  echo &"line       : {lineName}"
  echo &"intervalMs : {intervalMs}"
  echo &"activeLow  : {activeLow}"

  let gpioRes = openGpio(lineName, "nim_gpiod_poll_watch", activeLow)
  if gpioRes.isErr:
    echo gpioRes.error
    quit 1

  let gpio = gpioRes.value

  defer:
    gpio.close()

  let firstRes = gpio.getValueRes()
  if firstRes.isErr:
    echo firstRes.error
    quit 1

  var lastValue = firstRes.value
  echo &"{nowText()} value={lastValue} initial"

  while true:
    await sleepAsync(intervalMs)

    let valueRes = gpio.getValueRes()
    if valueRes.isErr:
      echo valueRes.error
      quit 1

    let value = valueRes.value
    if value != lastValue:
      echo &"{nowText()} value={value} changed from {lastValue}"
      lastValue = value

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
when isMainModule:
  waitFor main()
