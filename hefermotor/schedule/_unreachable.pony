use @pony_os_stderr[Pointer[U8]]()
use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @exit[None](status: I32)

primitive _Unreachable
  """
  Ends the process from a branch no input can reach. Prints the file, line
  and method to stderr and exits with 70, a code outside the ones the
  command uses for a verdict, so a run that got here is scored as a crash
  and never as an answer.
  """
  fun apply(loc: SourceLoc = __loc) =>
    @fprintf(
      @pony_os_stderr(),
      ("Unreachable code reached at %s:%lu in %s.%s\n" +
        "Please file an issue at " +
        "https://github.com/contact-red/hefermotor/issues\n").cstring(),
      loc.file().cstring(),
      loc.line(),
      loc.type_name().cstring(),
      loc.method_name().cstring())
    @exit(70)
