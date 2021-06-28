
# Our types

import std/[posix,deques,posix,heapqueue,tables,macros]
import cps

export POLLIN, POLLOUT

type
  C* = ref object of Continuation
    evq*: Evq

  EvqIo* = object
    fd*: SocketHandle
    c*: C

  EvqTimer* = object
    time*: float
    c*: C

  Evq* = ref object
    now*: float
    epfd*: cint
    work*: Deque[C]
    timers*: HeapQueue[EvqTimer]
    ios*: Table[SocketHandle, EvqIo]
    name*: string

proc trace2*(c: C, what: string, info: LineInfo) =
  echo "trace ", what, " ", info

proc dumpEvq*(c: C, what: string) {.cpsVoodoo.} =
  echo what, ": ", c.evq.name

proc pass*(cFrom, cTo: C): C =
  assert cFrom != nil
  assert cTo != nil
  cTo.evq = cFrom.evq
  cTo

template checkSyscall*(e: typed) =
  let r = e
  if r == -1:
    raise newException(OSError, "boom r=" & $r & ": " & $strerror(errno))
