
const libname = "libgpiod.so.2"

{.pragma: libgpiod, cdecl, dynlib: libname.}
{.pragma: prefixed, importc: "gpiod_$1".}
{.pragma: ctxless_prefixed, importc: "gpiod_ctxless_$1".}
{.pragma: chip_prefixed, importc: "gpiod_chip_$1".}
{.pragma: line_prefixed, importc: "gpiod_line_$1".}
{.pragma: samename, importc: "$1".}


type
  GpioChipStruct {.final, pure.} = object
  GpiodChip* = ptr GpioChipStruct
  GpiodLineStruct {.final, pure.} = object
  GpiodLine* = ptr GpiodLineStruct
  GpiodLineBulkStruct {.final, pure.} = object
  GpiodLineBulk* = ptr GpiodLineBulkStruct

proc find_line*(name: cstring, chipname: ptr cstring,
    chipname_size: csize_t, offset: ptr cuint): cint {.libgpiod, ctxless_prefixed.}

proc chip_open*(path: cstring): GpiodChip {.libgpiod, prefixed.}
proc chip_open_by_name*(name: cstring): GpiodChip {.libgpiod, prefixed.}
proc chip_open_by_number*(num: cuint): GpiodChip {.libgpiod, prefixed.}

proc close*(chip: GpiodChip) {.libgpiod, chip_prefixed.}
proc name*(chip: GpiodChip): cstring {.libgpiod, chip_prefixed.}
proc label*(chip: GpiodChip): cstring {.libgpiod, chip_prefixed.}
proc num_lines*(chip: GpiodChip): cuint {.libgpiod, chip_prefixed.}

proc get_line*(chip: GpiodChip, offset: cuint): GpiodLine {.libgpiod, chip_prefixed.}
proc find_line*(chip: GpiodChip, name: cstring): GpiodLine {.libgpiod, chip_prefixed.}

proc offset*(line: GpiodLine): cuint {.libgpiod, line_prefixed.}
proc name*(line: GpiodLine): cstring {.libgpiod, line_prefixed.}
proc consumer*(line: GpiodLine): cstring {.libgpiod, line_prefixed.}
proc direction*(line: GpiodLine): cint {.libgpiod, line_prefixed.}
proc active_state*(line: GpiodLine): cint {.libgpiod, line_prefixed.}
proc is_used*(line: GpiodLine): cint {.libgpiod, line_prefixed.}

type
  LineRequestConfig* {.importc: "struct gpiod_line_request_config",
      header: "<gpiod.h>".} = object
    consumer*: cstring
    request_type*: cint
    flags*: cint

func BIT(nr: cint): culong =
  return (1.culong shl nr)

type
  LineReq* {.pure.} = enum
    LirectionAsIs = 1
    DirectionInput
    DirectionOutput
    FallingEdge
    RisingEdge
    BothEdges
  LineFlag* {.pure.} = enum
    OpenDrain = BIT(0)
    OpenSource = BIT(1)
    ActiveLow = BIT(2)

proc request_input*(line: GpiodLine, consumer: cstring): cint
    {.libgpiod, line_prefixed.}
proc request_output*(line: GpiodLine, consumer: cstring, default_val: cint): cint
    {.libgpiod, line_prefixed.}
proc request_rising_edge_events*(line: GpiodLine, consumer: cstring): cint
    {.libgpiod, line_prefixed.}
proc request_falling_edge_events*(line: GpiodLine, consumer: cstring): cint
    {.libgpiod, line_prefixed.}
proc request_both_edges_events*(line: GpiodLine, consumer: cstring): cint
    {.libgpiod, line_prefixed.}
proc release*(line: GpiodLine) {.libgpiod, line_prefixed.}
proc is_requested*(line: GpiodLine): cint {.libgpiod, line_prefixed.}
proc is_free*(line: GpiodLine): cint {.libgpiod, line_prefixed.}
proc get_value*(line: GpiodLine): cint {.libgpiod, line_prefixed.}
proc set_value*(line: GpiodLine, value: cint): cint {.libgpiod, line_prefixed.}

proc `=destroy`(line: GpiodLineStruct) =
  (addr line).release()

type
  EventType* {.pure.} = enum
    RisingEdge = 1
    FallingEdge
  Timespec* {.importc: "struct timespec", header: "<sys/time.h>",
            final, pure.} = object
    tv_sec*: clong
    tv_nsec*: clong
  LineEvent* {.importc: "struct gpiod_line_event", header: "<gpiod.h>".} = object
    ts*: Timespec
    event_type*: EventType

proc event_read*(line: GpiodLine, event: ptr LineEvent): cint {.libgpiod, line_prefixed.}
proc event_get_fd*(line: GpiodLine): cint {.libgpiod, line_prefixed.}
