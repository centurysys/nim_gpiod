type
  Edge* {.pure.} = enum
    Falling
    Rising
    Both

  EventEdge* {.pure.} = enum
    Falling
    Rising

  Event* = object
    ## Compatibility event object.
    ##
    ## ``value`` exists for old nim_gpiod users.  For raw edge events it is
    ## derived from ``edge``.  The old ``wait_event`` compatibility wrapper
    ## overwrites it with ``getValue()`` after debounce has settled.
    edge*: Edge
    value*: int
    timestampNs*: uint64
    seqno*: uint32
    lineSeqno*: uint32

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc toEdge*(edge: EventEdge): Edge =
  case edge
  of EventEdge.Falling:
    result = Edge.Falling
  of EventEdge.Rising:
    result = Edge.Rising

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc toEventEdge*(edge: Edge): EventEdge =
  case edge
  of Edge.Falling:
    result = EventEdge.Falling
  of Edge.Rising:
    result = EventEdge.Rising
  of Edge.Both:
    result = EventEdge.Rising

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc valueFromEdge*(edge: Edge): int =
  case edge
  of Edge.Falling:
    result = 0
  of Edge.Rising:
    result = 1
  of Edge.Both:
    result = 0
