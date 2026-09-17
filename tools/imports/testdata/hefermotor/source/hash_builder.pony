primitive HashBuilder
  fun of(s: String): USize => s.hash()
  fun of64(s: String): U64 => s.hash64()
  fun spaced(s: String): USize => s.hash ( )
