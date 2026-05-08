import std/asyncdispatch
import std/strformat

import ./bindings/c_api
import ./errors
import ./types

export errors
export types

type
  AsyncGpioObj = object
    gpio: ptr Ngpio
    fd: AsyncFD
    lineName: string
    consumer: string
    activeLow: bool

  AsyncGpio* = ref AsyncGpioObj

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc unregisterNoThrow(fd: var AsyncFD) {.raises: [].} =
  if fd == AsyncFD(-1):
    return

  try:
    fd.unregister()
  except CatchableError:
    discard

  fd = AsyncFD(-1)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc releaseEventsNoThrow(gpio: ptr Ngpio) {.raises: [].} =
  if gpio == nil:
    return

  discard ngpioReleaseEvents(gpio)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc closeGpioNoThrow(gpio: var ptr Ngpio) {.raises: [].} =
  if gpio == nil:
    return

  discard ngpioReleaseEvents(gpio)
  ngpioClose(gpio)
  gpio = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `=destroy`*(self: var AsyncGpioObj) {.raises: [].} =
  unregisterNoThrow(self.fd)
  closeGpioNoThrow(self.gpio)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc lastError(gpio: ptr Ngpio): string =
  let msg = ngpioLastError(gpio)
  if msg == nil:
    result = "unknown GPIO error"
  else:
    result = $msg

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc lastGlobalError(): string =
  let msg = ngpioLastErrorGlobal()
  if msg == nil:
    result = "unknown GPIO error"
  else:
    result = $msg

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc toNgpioEdge(edge: Edge): NgpioEdge =
  case edge
  of Edge.Falling:
    result = NgpioEdgeFalling
  of Edge.Rising:
    result = NgpioEdgeRising
  of Edge.Both:
    result = NgpioEdgeBoth

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc toEventEdge(edge: NgpioEventEdge): EventEdge =
  case edge
  of NgpioEventFalling:
    result = EventEdge.Falling
  of NgpioEventRising:
    result = EventEdge.Rising

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc cleanupEventRequest(self: AsyncGpio) =
  if self.isNil:
    return

  unregisterNoThrow(self.fd)
  releaseEventsNoThrow(self.gpio)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc openGpio*(
  lineName: string,
  consumer = "nim_gpiod",
  activeLow = false
): GE[AsyncGpio] =
  let gpio = ngpioOpenByLineName(
    lineName.cstring,
    consumer.cstring,
    cint(if activeLow: 1 else: 0)
  )

  if gpio == nil:
    return fail[AsyncGpio](
      ekOpen,
      &"failed to open GPIO line '{lineName}': {lastGlobalError()}"
    )

  result = GE[AsyncGpio].ok(AsyncGpio(
    gpio: gpio,
    fd: AsyncFD(-1),
    lineName: lineName,
    consumer: consumer,
    activeLow: activeLow
  ))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc openGpioByChipOffset*(
  chipPath: string,
  offset: uint,
  consumer = "nim_gpiod",
  activeLow = false
): GE[AsyncGpio] =
  let gpio = ngpioOpenByChipOffset(
    chipPath.cstring,
    cuint(offset),
    consumer.cstring,
    cint(if activeLow: 1 else: 0)
  )

  if gpio == nil:
    return fail[AsyncGpio](
      ekOpen,
      &"failed to open GPIO chip '{chipPath}' offset {offset}: {lastGlobalError()}"
    )

  result = GE[AsyncGpio].ok(AsyncGpio(
    gpio: gpio,
    fd: AsyncFD(-1),
    lineName: &"{chipPath}:{offset}",
    consumer: consumer,
    activeLow: activeLow
  ))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc newGpio*(
  lineName: string,
  consumer = "nim_gpiod",
  activeLow = false
): AsyncGpio =
  let res = openGpio(lineName, consumer, activeLow)
  if res.isErr:
    raise newException(OSError, $res.error)

  result = res.value

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc newGpioByChipOffset*(
  chipPath: string,
  offset: uint,
  consumer = "nim_gpiod",
  activeLow = false
): AsyncGpio =
  let res = openGpioByChipOffset(chipPath, offset, consumer, activeLow)
  if res.isErr:
    raise newException(OSError, $res.error)

  result = res.value

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc isOpen*(self: AsyncGpio): bool =
  result = (not self.isNil) and self.gpio != nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getValueRes*(self: AsyncGpio): GE[int] =
  if self.isNil or self.gpio == nil:
    return fail[int](ekInvalidState, "GPIO is not open")

  var value: cint
  let rc = ngpioGetValue(self.gpio, addr value)
  if rc < 0:
    return fail[int](
      ekRead,
      &"failed to read GPIO '{self.lineName}': {lastError(self.gpio)}"
    )

  result = GE[int].ok(int(value))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getValue*(self: AsyncGpio): int =
  let res = self.getValueRes()
  if res.isErr:
    raise newException(OSError, $res.error)

  result = res.value

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitEventResRaw(self: AsyncGpio, edge: Edge): Future[GE[Event]] =
  let retFuture = newFuture[GE[Event]]("nim_gpiod.waitEventResRaw")

  if self.isNil or self.gpio == nil:
    retFuture.complete(fail[Event](ekInvalidState, "GPIO is not open"))
    return retFuture

  if self.fd != AsyncFD(-1):
    retFuture.complete(fail[Event](
      ekInvalidState,
      &"GPIO '{self.lineName}' is already waiting for an edge event"
    ))
    return retFuture

  let reqRc = ngpioRequestEdgeEvents(self.gpio, toNgpioEdge(edge))
  if reqRc < 0:
    retFuture.complete(fail[Event](
      ekRequest,
      &"failed to request edge events for GPIO '{self.lineName}': {lastError(self.gpio)}"
    ))
    return retFuture

  let rawFd = ngpioGetEventFd(self.gpio)
  if rawFd < 0:
    discard ngpioReleaseEvents(self.gpio)
    retFuture.complete(fail[Event](
      ekRequest,
      &"failed to get event fd for GPIO '{self.lineName}': {lastError(self.gpio)}"
    ))
    return retFuture

  self.fd = AsyncFD(rawFd)
  self.fd.register()

  proc cb(fd: AsyncFD): bool =
    var rawEvent: NgpioEvent

    let readRc = ngpioReadEvent(self.gpio, addr rawEvent)

    self.cleanupEventRequest()

    if retFuture.finished:
      return true

    if readRc < 0:
      retFuture.complete(fail[Event](
        ekRead,
        &"failed to read edge event for GPIO '{self.lineName}': {lastError(self.gpio)}"
      ))
      return true

    let ev = Event(
      edge: toEventEdge(rawEvent.edge),
      timestampNs: rawEvent.timestampNs,
      seqno: rawEvent.seqno,
      lineSeqno: rawEvent.lineSeqno
    )

    retFuture.complete(GE[Event].ok(ev))
    return true

  addRead(self.fd, cb)

  result = retFuture

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitEventRes*(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[GE[Event]] {.async.} =
  let fut = self.waitEventResRaw(edge)

  if timeoutMs < 0:
    result = await fut
    return

  let completed = await fut.withTimeout(timeoutMs)
  if completed:
    result = fut.read()
    return

  self.cleanupEventRequest()
  result = fail[Event](
    ekTimeout,
    &"timeout while waiting for GPIO '{self.lineName}' edge event"
  )

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitEventInfo*(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Event] {.async.} =
  let res = await self.waitEventRes(edge, timeoutMs)
  if res.isErr:
    raise newException(OSError, $res.error)

  result = res.value

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitEvent*(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Edge] {.async.} =
  let ev = await self.waitEventInfo(edge, timeoutMs)
  result = toEdge(ev.edge)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitEdge*(
  self: AsyncGpio,
  edge: Edge,
  timeoutMs = -1
): Future[Edge] =
  result = self.waitEvent(edge, timeoutMs)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc wait_edge*(
  self: AsyncGpio,
  edge: Edge
): Future[Edge] =
  result = self.waitEvent(edge)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(self: AsyncGpio) =
  if self.isNil:
    return

  self.cleanupEventRequest()
  closeGpioNoThrow(self.gpio)
