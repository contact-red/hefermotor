"""
A package docstring.
"""
use "endcollections" if linux
use @strlen[USize](s: Pointer[U8] tag)

class \packed\ Point[A: Any val]
  var x: F64 = 0

  fun ref move(dx: F64): F64 =>
    x = x + dx

actor Main
  new create(env: Env) =>
    /* a nested comment */
    env.out.print("h\tello") // a line comment
