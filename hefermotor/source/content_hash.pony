use "format"

class val ContentHash is (Comparable[ContentHash] & Stringable)
  """
  The only identity that crosses a cache boundary. It is an identity, not
  an integrity check: 64 bits of SipHash-2-4 under the runtime's fixed,
  public key, so two inputs with the same hash are treated as the same
  input.

  Only this package makes one, and only by hashing bytes: `SourceFile`
  hashes a file's content, `HashBuilder` hashes a sequence of fields. An
  integer cannot be wrapped as a hash; what goes into the bytes is the
  caller's choice, and a hash over a path differs between checkouts, as
  the path does.
  """
  let _value: U64

  new val _create(value: U64) =>
    _value = value

  fun bytes(): Array[U8] val =>
    """
    The hash as eight bytes, least significant first.
    """
    let v = _value
    recover val
      let out = Array[U8](8)
      var i: U64 = 0
      while i < 8 do
        out.push(((v >> (i * 8)) and 0xFF).u8())
        i = i + 1
      end
      out
    end

  fun hex(): String =>
    """
    The hash as sixteen lowercase hexadecimal digits, zero padded.
    """
    Format.int[U64](_value where fmt = FormatHexSmallBare, width = 16,
      fill = '0')

  fun string(): String iso^ =>
    """
    The same sixteen digits as `hex`.
    """
    Format.int[U64](_value where fmt = FormatHexSmallBare, width = 16,
      fill = '0')

  fun eq(that: ContentHash box): Bool =>
    _value == that._value

  fun lt(that: ContentHash box): Bool =>
    _value < that._value

  fun hash(): USize =>
    """
    For in-process maps only; its width follows the machine word.
    """
    _value.usize()

  fun _u64(): U64 =>
    _value
