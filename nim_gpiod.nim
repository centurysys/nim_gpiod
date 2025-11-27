import std/asyncdispatch
import std/strformat
import nim_gpiodpkg/libgpiod

type
  Edge* {.pure.} = enum
    Falling = LineReq.FallingEdge
    Rising = LineReq.RisingEdge
    Both = LineReq.BothEdges
  Event* = object
    edge*: Edge
    value*: int
  AsyncGpioObj = object
    chip: GpiodChip
    line: GpiodLine
    fd: AsyncFD
    consumer: string
    fut_edge: Future[Edge]
  AsyncGpio* = ref AsyncGpioObj

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc `=destroy`(self: AsyncGpioObj) =
  if self.fd != AsyncFD(-1):
    try:
      self.fd.unregister()
    except:
      discard
  if self.line.is_requested() == 1:
    self.line.release()
  self.chip.close()

#-------------------------------------------------------------------------------
# Constructor
#-------------------------------------------------------------------------------
proc newGpio*(lineName: string, consumer: string): AsyncGpio =
  const namelen = 32
  var
    chipname = newString(namelen)
    offset: cuint
  let res = find_line(lineName.cstring, cast[ptr cstring](addr chipname[0]),
      namelen, addr offset)
  if res != 1:
    echo &"find_line() failed with {res}"
    return
  let chip = chip_open_by_name(chipname.cstring)
  if chip.isNil:
    echo &"chip_open_by_name({chipname}) failed."
    return
  let line = chip.get_line(offset)
  if line.is_used() == 1:
    return
  result = new AsyncGpio
  result.chip = chip
  result.line = line
  result.consumer = consumer
  result.fd = AsyncFD(-1)

#-------------------------------------------------------------------------------
# API:
#-------------------------------------------------------------------------------
proc getValue*(self: AsyncGpio): int =
  let requested = self.line.is_requested()
  if requested != 1:
    discard self.line.request_input(self.consumer.cstring)
  result = self.line.get_value().int
  if requested != 1:
    self.line.release()

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc waitEdge(self: AsyncGpio, edge: Edge): Future[Edge] =
  var retFuture = newFuture[Edge]("gpiod_event")

  proc cb(fd: AsyncFD): bool =
    var event: LineEvent
    discard self.line.event_read(addr event)
    let edgeVal = case event.event_type
      of EventType.RisingEdge: Edge.Rising
      else: Edge.Falling
    retFuture.complete(edgeVal)
    self.fd.unregister()
    self.fd = AsyncFD(-1)
    return true

  if self.fd == AsyncFD(-1):
    var res: cint
    case edge
      of Edge.Falling:
        res = self.line.request_falling_edge_events(self.consumer.cstring)
      of Edge.Rising:
        res = self.line.request_rising_edge_events(self.consumer.cstring)
      of Edge.Both:
        res = self.line.request_both_edges_events(self.consumer.cstring)
    let fd = self.line.event_get_fd()
    self.fd = fd.AsyncFD
    self.fd.register()
  addRead(self.fd, cb)
  return retFuture

#-------------------------------------------------------------------------------
# API:
#-------------------------------------------------------------------------------
proc waitEvent*(self: AsyncGpio, edge: Edge, debounce_ms: int):
    Future[Event] {.async.} =
  var evEdge: Edge
  if self.fut_edge.isNil:
    self.fut_edge = self.waitEdge(edge)
  evEdge = await self.fut_edge
  self.fut_edge = nil
  while true:
    self.fut_edge = self.waitEdge(edge)
    let res = await withTimeout(self.fut_edge, debounce_ms)
    if res:
      # maybe chattering occurs
      evEdge = self.fut_edge.read()
      self.fut_edge = nil
    else:
      break
  result.value = self.getValue()
  result.edge = evEdge


when isMainModule:
  import std/times

  proc asyncMain() {.async.} =
    let di0 = newGpio("DI0", "NimGPIO")
    if di0.isNil:
      echo "newGpio failed."
      quit(1)
    while true:
      echo "wait event..."
      let event = await di0.waitEvent(Edge.Both, 10)
      let now = now().format("yyyy-MM-dd HH:mm:ss")
      echo &"*** {now}: Event! (edge: {event.edge}, value: {event.value})"

  waitFor asyncMain()
