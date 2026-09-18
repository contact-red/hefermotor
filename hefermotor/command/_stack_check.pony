use parse = "../parse"

use @getrlimit[I32](resource: I32, rlim: Pointer[U64] tag)
use @sysconf[ISize](name: I32)
use @pthread_attr_init[I32](attr: Pointer[U8] tag)
use @pthread_attr_getstacksize[I32](attr: Pointer[U8] tag,
  size: Pointer[USize] tag)
use @pthread_attr_destroy[I32](attr: Pointer[U8] tag)

interface val StackLimit
  """
  What `Run` asks before discovery: `None` when the scheduler threads'
  stack is enough for the parser, else the refusal to print.
  """
  fun apply(): (None | StackTooSmall)

class val StackTooSmall
  """
  The scheduler threads' stack is below what the parser needs: the
  stack each thread gets, and whether the soft `RLIMIT_STACK` was
  unlimited, in which case the C library's default applied.
  """
  let thread_stack: USize
  let unlimited: Bool

  new val create(thread_stack': USize, unlimited': Bool) =>
    thread_stack = thread_stack'
    unlimited = unlimited'

  fun string(): String iso^ =>
    let need = parse.StackNeed() / 1024
    (recover String end)
      .> append("hefermotor: each scheduler thread gets a ")
      .> append((thread_stack / 1024).string())
      .> append(" KiB stack")
      .> append(
        if unlimited then
          " (ulimit -s is unlimited, so the C library's default applies)"
        else
          ""
        end)
      .> append(" and the parser needs ")
      .> append(need.string())
      .> append(" KiB: run under a finite `ulimit -s` of ")
      .> append(need.string())
      .> append(" or more")

primitive StackCheck is StackLimit
  """
  The process's own limits, read as the runtime reads them: a scheduler
  thread gets the soft `RLIMIT_STACK` when it is finite and at least
  `PTHREAD_STACK_MIN`, else the C library's default thread stack, which
  is 2 MiB on glibc when the limit is unlimited and 128 KiB on musl
  whatever the limit. Returns `StackTooSmall` when that is below
  `parse.StackNeed()`.
  """
  fun apply(): (None | StackTooSmall) =>
    check(_soft_limit(), _pthread_stack_min(), _libc_default())

  fun check(soft_limit: (U64 | None), stack_min: U64, libc_default: USize)
    : (None | StackTooSmall)
  =>
    """
    `None` when the stack a scheduler thread gets from these is at
    least `parse.StackNeed()`, else the refusal; `soft_limit` is `None`
    when `RLIMIT_STACK` is unlimited.
    """
    let stack = thread_stack(soft_limit, stack_min, libc_default)
    if stack < parse.StackNeed() then
      StackTooSmall(stack, soft_limit is None)
    else
      None
    end

  fun thread_stack(soft_limit: (U64 | None), stack_min: U64,
    libc_default: USize)
    : USize
  =>
    """
    The stack a scheduler thread gets: the soft limit when it is finite
    and at least `stack_min`, else the C library's default.
    """
    match soft_limit
    | let cur: U64 if cur >= stack_min => cur.usize()
    else
      libc_default
    end

  fun _pthread_stack_min(): U64 =>
    // _SC_THREAD_STACK_MIN: 75 on Linux, 93 on macOS and the BSDs.
    let got = @sysconf(ifdef osx or bsd then I32(93) else I32(75) end)
    if got < 0 then _Unreachable() end
    got.u64()

  fun _soft_limit(): (U64 | None) =>
    let rlim = Array[U64].init(0, 2)
    if @getrlimit(_rlimit_stack(), rlim.cpointer()) != 0 then
      _Unreachable()
    end
    let cur = try rlim(0)? else _Unreachable(); 0 end
    if cur == _rlim_infinity() then None else cur end

  fun _libc_default(): USize =>
    let attr = Array[U8].init(0, 128)
    if @pthread_attr_init(attr.cpointer()) != 0 then _Unreachable() end
    var size: USize = 0
    if @pthread_attr_getstacksize(attr.cpointer(), addressof size) != 0 then
      _Unreachable()
    end
    @pthread_attr_destroy(attr.cpointer())
    size

  fun _rlimit_stack(): I32 =>
    3

  fun _rlim_infinity(): U64 =>
    ifdef osx or bsd then 0x7fff_ffff_ffff_ffff else U64.max_value() end
