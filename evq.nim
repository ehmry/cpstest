
# Minimal event queue implementation supporting a work queue, I/O and timers


import std/[tables,heapqueue,deques,posix,epoll,monotimes]
import cps
import types


proc newEvq*(): Evq =
  Evq(
    now: getMonoTime().ticks.float / 1.0e9,
    epfd: epoll_create(1),
    name: "Lebowski",
  )

template `<`(a, b: EvqTimer): bool =
  a.time < b.time

proc push*(evq: Evq, c: C) =
  ## Push work to the back of the work queue
  assert c != nil
  assert evq != nil
  c.evq = evq
  evq.work.addLast c

proc jield*(c: C): C {.cpsMagic.} =
  ## Suspend continuation until the next evq iteration - cooperative schedule
  c.evq.work.addLast c

proc iowait*[T](c: C, conn: T, events: int): C {.cpsMagic.} =
  ## Suspend continuation until I/O event triggered
  assert c != nil
  assert c.evq != nil
  c.evq.ios[conn.fd] = EvqIo(fd: conn.fd, c: c)
  var ee = EpollEvent(events: events.uint32, data: EpollData(u64: conn.fd.uint64))
  checkSyscall epoll_ctl(c.evq.epfd, EPOLL_CTL_ADD, conn.fd.cint, ee.addr)

proc sleep*(c: C, delay: float): C {.cpsMagic.} =
  ## Suspend continuation until timer expires
  assert c != nil
  assert c.evq != nil
  c.evq.timers.push EvqTimer(c: c, time: c.evq.now + delay)

proc getEvq*(c: C): Evq {.cpsVoodoo.} =
  ## Retrieve event queue for the current contiunation
  c.evq

proc run*(evq: Evq) =

  ## Run the event queue
  while true:

    # Trampoline all work
    var work = move evq.work
    while work.len > 0:
      discard trampoline(work.popFirst)

    # Calculate timeout until first timer
    evq.now = getMonoTime().ticks.float / 1.0e9
    var timeout: cint = -1
    if evq.timers.len > 0:
      let timer = evq.timers[0]
      timeout = cint(1000 * (timer.time - evq.now))
      timeout = max(timeout, 0)

    # Wait for timers or I/O
    var es: array[8, EpollEvent]
    let n = epoll_wait(evq.epfd, es[0].addr, es.len.cint, timeout)

    # Move expired timer continuations to the work queue
    evq.now = getMonoTime().ticks.float / 1.0e9
    while evq.timers.len > 0 and evq.timers[0].time <= evq.now:
      evq.push evq.timers.pop.c

    # Move triggered I/O continuations to the work queue
    for i in 0..<n:
      let fd = es[i].data.u64.SocketHandle
      let io = evq.ios[fd]
      checkSyscall epoll_ctl(evq.epfd, EPOLL_CTL_DEL, io.fd.cint, nil)
      evq.ios.del fd
      evq.push io.c

