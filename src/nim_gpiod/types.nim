type
  Edge* {.pure.} = enum
    Falling
    Rising
    Both

  EventEdge* {.pure.} = enum
    Falling
    Rising

  Event* = object
    edge*: EventEdge
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
