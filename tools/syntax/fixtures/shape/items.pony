"""
Package docstring with "quotes", a \ backslash and a
second line.
"""
use "collections"
use c = "collections/persistent" if linux
use "x" if "y"
use "z" if (linux or osx)
use "w" if ("a"; linux)
use @f[U8 \a\](x: U8 \b\ = 1, ...)?
use g = @"str name"[None]() if windows
use @h[U8](...)
use @k[U8](a: U8)
use @l[(U8 | U16) \x\]()
use @m[3 \x\]()

type Alias is (A | B | C)

interface I
trait T
struct S
primitive P
  """Primitive docstring"""

class \packed, nodoc\ @ iso Foo[A: Any val = None, B]
  is (Named & Equatable[Foo[A, B]])
  """Class docstring"""
  let x: (U8 | (this->Array[U8] box, {(A): B ?} val^))
  var y: pkg.T[3, U8 #read] iso^ = 1 "field docstring"
  embed z: U8 = 2
  let w: U8 "docstring without a value"
  let v: U8 = ("s"; 1)

  new create() => "s"; 2
  fun \nodoc\ box f[T](a: U8, b: U8 = 2, ...): U8 ? => 1
  fun g() => "only"
  be h() "before the arrow" => "in the body"; 1
  fun i(): iso => "s"
    2
  fun @bare(): U8 => 1
  fun j(): A! ?
  fun k(a: U8, b: U8 = 2): U8 => 1; 2
  be h2() => "doc"; 1
  fun d() "doc" => 1
