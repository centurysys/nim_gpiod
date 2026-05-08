import std/strformat

import results
export results

type
  ErrKind* = enum
    ekSuccess = "Succeeded"
    ekOpen = "Open Error"
    ekRequest = "Request Error"
    ekRead = "Read Error"
    ekInvalid = "Invalid Argument"
    ekInvalidState = "Invalid State"
    ekTimeout = "Timeout"
    ekUnsupported = "Unsupported"
    ekNotFound = "Not Found"
    ekType = "Type Error"
    ekOther = "Other Error"

  Error* = ref object
    kind*: ErrKind
    msg*: string
    #trace*: seq[string]

  GE*[T] = Result[T, Error]

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(err: Error): string =
  if err.isNil:
    result = "Error: nil"
  else:
    result = &"Error: {err.kind}: {err.msg}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc makeError*(kind: ErrKind, msg: string): Error =
  result = Error(kind: kind, msg: msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc withTrace(err: Error, where: static[string]): Error {.inline.} =
  result = err
  #result.trace.add(where)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc trace*[T](res: GE[T], where: static[string]): GE[T] {.inline.} =
  if res.isErr:
    result = err(res.error.withTrace(where))
  else:
    result = res

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc errKind*[T](res: GE[T]): ErrKind =
  if res.isErr:
    result = res.error.kind
  else:
    result = ekSuccess

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc errMsg*[T](res: GE[T]): string =
  if res.isErr:
    result = res.error.msg
  else:
    result = "No Error"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc okVoid*(): GE[void] =
  result = ok()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc fail*[T](kind: ErrKind, msg: string): GE[T] =
  result = err(makeError(kind, msg))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc failVoid*(kind: ErrKind, msg: string): GE[void] =
  result = err(makeError(kind, msg))
