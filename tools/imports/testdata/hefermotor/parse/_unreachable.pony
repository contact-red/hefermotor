use @exit[None](code: I32)

primitive _Unreachable
  fun apply() => @exit(70)
