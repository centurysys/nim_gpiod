import std/asyncdispatch
import std/os
import std/strformat
import std/strutils

import nim_gpiod

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc usage() =
  let app = getAppFilename().extractFilename()
  echo &"Usage: {app} [line-name] [edge] [timeout-ms]"
  echo ""
  echo "Arguments:"
  echo "  line-name   GPIO line name. Default: SIM_CD"
  echo "  edge        rising | falling | both. Default: both"
  echo "  timeout-ms  Timeout in milliseconds. Default: -1"
  echo ""
  echo "Examples:"
  echo &"  {app}"
  echo &"  {app} SIM_CD both"
  echo &"  {app} SIM2_CD falling 10000"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc parseEdge(s: string): Edge =
  case s
  of "falling", "Falling", "fall":
    result = Edge.Falling
  of "rising", "Rising", "rise":
    result = Edge.Rising
  of "both", "Both":
    result = Edge.Both
  else:
    raise newException(ValueError, &"invalid edge: {s}")

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

  let edge =
    if paramCount() >= 2: parseEdge(paramStr(2))
    else: Edge.Both

  let timeoutMs =
    if paramCount() >= 3: parseInt(paramStr(3))
    else: -1

  echo &"line      : {lineName}"
  echo &"edge      : {edge}"
  echo &"timeoutMs : {timeoutMs}"

  let gpioRes = openGpio(lineName, "nim_gpiod_event_watch")
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

  echo &"initial   : {valueRes.value}"
  echo "waiting..."

  let evRes = await gpio.waitEventRes(edge, timeoutMs)
  if evRes.isErr:
    echo evRes.error
    quit 1

  let ev = evRes.value
  echo &"event     : {ev.edge}"
  echo &"timestamp : {ev.timestampNs} ns"
  echo &"seqno     : {ev.seqno}"
  echo &"lineSeqno : {ev.lineSeqno}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
when isMainModule:
  waitFor main()
