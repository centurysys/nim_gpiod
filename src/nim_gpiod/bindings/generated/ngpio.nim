# ------------------------------------------------------------------------------
# Generated-style binding for src/nim_gpiod/shim/ngpio.h
#
# This file is intentionally kept small and stable so normal users do not need
# Futhark/libclang at build time.
# ------------------------------------------------------------------------------

{.push header: "ngpio.h".}

type
  Ngpio* {.importc: "ngpio_t".} = object

  NgpioEdge* {.size: sizeof(cint), importc: "ngpio_edge_t".} = enum
    NgpioEdgeRising = 1,
    NgpioEdgeFalling = 2,
    NgpioEdgeBoth = 3

  NgpioEventEdge* {.size: sizeof(cint), importc: "ngpio_event_edge_t".} = enum
    NgpioEventRising = 1,
    NgpioEventFalling = 2

  NgpioEvent* {.importc: "ngpio_event_t".} = object
    edge* {.importc: "edge".}: NgpioEventEdge
    timestampNs* {.importc: "timestamp_ns".}: uint64
    seqno* {.importc: "seqno".}: uint32
    lineSeqno* {.importc: "line_seqno".}: uint32

proc ngpioOpenByLineName*(
  lineName: cstring;
  consumer: cstring;
  activeLow: cint
): ptr Ngpio
  {.cdecl, importc: "ngpio_open_by_line_name".}

proc ngpioOpenByChipOffset*(
  chipPath: cstring;
  offset: cuint;
  consumer: cstring;
  activeLow: cint
): ptr Ngpio
  {.cdecl, importc: "ngpio_open_by_chip_offset".}

proc ngpioGetValue*(
  gpio: ptr Ngpio;
  value: ptr cint
): cint
  {.cdecl, importc: "ngpio_get_value".}

proc ngpioRequestEdgeEvents*(
  gpio: ptr Ngpio;
  edge: NgpioEdge
): cint
  {.cdecl, importc: "ngpio_request_edge_events".}

proc ngpioGetEventFd*(
  gpio: ptr Ngpio
): cint
  {.cdecl, importc: "ngpio_get_event_fd".}

proc ngpioReadEvent*(
  gpio: ptr Ngpio;
  event: ptr NgpioEvent
): cint
  {.cdecl, importc: "ngpio_read_event".}

proc ngpioReleaseEvents*(
  gpio: ptr Ngpio
): cint
  {.cdecl, importc: "ngpio_release_events".}

proc ngpioLastError*(
  gpio: ptr Ngpio
): cstring
  {.cdecl, importc: "ngpio_last_error".}

proc ngpioLastErrorGlobal*(): cstring
  {.cdecl, importc: "ngpio_last_error_global".}

proc ngpioClose*(
  gpio: ptr Ngpio
)
  {.cdecl, importc: "ngpio_close".}

{.pop.}
