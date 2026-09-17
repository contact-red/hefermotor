use "format"
use fmt = "format"
use "format" if windows
use "collections"

primitive Fmt
  fun of(s: String): USize => s.hash()
