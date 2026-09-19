primitive StringLiteralValue
  """
  The value of a string literal's text, as ponyc's lexer gives it to
  the passes after it: quotes stripped; for the ordinary quoted form,
  escapes decoded, a bad escape dropping out as ponyc drops it after
  reporting; for the triple-quoted form, no escapes and ponyc's
  `normalise_string` applied: a leading newline dropped, the common
  leading whitespace of every line stripped, and a last line holding
  only whitespace emptied. Text that is not a string literal is
  returned as it is.
  """
  fun apply(text: String val): String val =>
    if (text.size() >= 6) and
      (text.compare_sub("\"\"\"", 3) is Equal) and
      (text.compare_sub("\"\"\"", 3, (text.size() - 3).isize()) is Equal)
    then
      _normalise(text.substring(3, text.size().isize() - 3))
    elseif (text.size() >= 2) and (text.compare_sub("\"", 1) is Equal) then
      _decode(text.substring(1, text.size().isize() - 1))
    else
      text
    end

  fun of(node: Node): String val =>
    """
    The value of the literal `node` covers.
    """
    apply(node.text())

  fun _decode(text: String val): String val =>
    if not text.contains("\\") then
      return text
    end
    let out = recover iso String(text.size()) end
    var i: USize = 0
    while i < text.size() do
      let c = try text(i)? else break end
      if c != '\\' then
        out.push(c)
        i = i + 1
        continue
      end
      let e = try text(i + 1)? else 0 end
      i = i + 2
      match e
      | 'a' => out.push(0x07)
      | 'b' => out.push(0x08)
      | 'e' => out.push(0x1B)
      | 'f' => out.push(0x0C)
      | 'n' => out.push('\n')
      | 'r' => out.push('\r')
      | 't' => out.push('\t')
      | 'v' => out.push(0x0B)
      | '\\' => out.push('\\')
      | '0' => out.push(0)
      | '"' => out.push('"')
      | 'x' | 'u' | 'U' =>
        let digits: USize =
          if e == 'x' then 2 elseif e == 'u' then 4 else 6 end
        (let value, let used) = _hex(text, i, digits)
        // A whole escape in range is its value UTF-8 encoded, as
        // ponyc's `append_utf8` writes it; a refused one is nothing.
        if (used == digits) and (value <= 0x10FFFF) then
          out.append(_utf8(value))
        end
        i = i + used
      end
    end
    consume out

  fun _utf8(value: U32): Array[U8] val =>
    """
    ponyc's `append_utf8`: the code point in one to four bytes by its
    range, a surrogate included as it is. The stdlib's `push_utf32`
    writes U+FFFD for a surrogate, which ponyc does not.
    """
    recover val
      let out = Array[U8](4)
      if value <= 0x7F then
        out.push(value.u8())
      elseif value <= 0x7FF then
        out.push(0xC0 or (value >> 6).u8())
        out.push(0x80 or (value and 0x3F).u8())
      elseif value <= 0xFFFF then
        out.push(0xE0 or (value >> 12).u8())
        out.push(0x80 or ((value >> 6) and 0x3F).u8())
        out.push(0x80 or (value and 0x3F).u8())
      else
        out.push(0xF0 or (value >> 18).u8())
        out.push(0x80 or ((value >> 12) and 0x3F).u8())
        out.push(0x80 or ((value >> 6) and 0x3F).u8())
        out.push(0x80 or (value and 0x3F).u8())
      end
      out
    end

  fun _hex(text: String val, from: USize, digits: USize): (U32, USize) =>
    """
    The value of up to `digits` hex digits starting at `from`, and how
    many there were.
    """
    var value: U32 = 0
    var used: USize = 0
    while used < digits do
      let c = try text(from + used)? else break end
      let d: U32 =
        if (c >= '0') and (c <= '9') then (c - '0').u32()
        elseif (c >= 'a') and (c <= 'f') then ((c - 'a') + 10).u32()
        elseif (c >= 'A') and (c <= 'F') then ((c - 'A') + 10).u32()
        else break
        end
      value = (value * 16) + d
      used = used + 1
    end
    (value, used)

  fun _normalise(text: String val): String val =>
    """
    ponyc's `normalise_string` over the text between the quotes. A
    literal on one line is untouched.
    """
    if not text.contains("\n") then
      return text
    end
    var body = text
    if body.at("\r\n") then
      body = body.trim(2)
    elseif body.at("\n") then
      body = body.trim(1)
    end
    let indent = _common_indent(body)
    let out = recover iso String(body.size()) end
    for line in _Lines(body) do
      // An empty line is kept; every other line loses the indent, or
      // all of itself when it is shorter, its newline included: ponyc
      // counts the newline in the line's length when it clips the cut.
      if (line.size() > 0) and (line.compare_sub("\n", 1) isnt Equal) then
        let trim = indent.min(line.size())
        out.append(line, trim)
      else
        out.append(line)
      end
    end
    _trim_trailing_line(consume out)

  fun _common_indent(body: String val): USize =>
    """
    The shortest run of leading spaces and tabs over the lines that
    hold a byte C's `isspace` rejects; the body's size when no line
    does. ponyc measures a line's indent up to its first byte that is
    not a space or a tab, and counts the line only when that byte is
    not whitespace at all.
    """
    var indent = body.size()
    var this_line: USize = 0
    var in_leading = true
    for c in body.values() do
      if in_leading then
        if (c == ' ') or (c == '\t') then
          this_line = this_line + 1
        else
          if not _is_c_space(c) then
            indent = indent.min(this_line)
          end
          in_leading = false
        end
      end
      if c == '\n' then
        this_line = 0
        in_leading = true
      end
    end
    indent

  fun _trim_trailing_line(text: String iso): String val =>
    """
    Drop the whitespace after the last newline when only whitespace
    follows it, as ponyc trims a trailing line of whitespace; the first
    byte is never read, as ponyc's loop stops before it.
    """
    var i = text.size()
    var trim: USize = 0
    while i > 1 do
      i = i - 1
      let c = try text(i)? else _Unreachable(); 0 end
      if c == '\n' then
        text.truncate(text.size() - trim)
        break
      elseif _is_c_space(c) then
        trim = trim + 1
      else
        break
      end
    end
    consume text

  fun _is_c_space(c: U8): Bool =>
    (c == ' ') or (c == '\t') or (c == '\n') or (c == '\r') or (c == 0x0B)
      or (c == 0x0C)

class _Lines is Iterator[String val]
  """
  The lines of a text, each with its newline where it has one.
  """
  let _text: String val
  var _at: USize = 0

  new create(text: String val) =>
    _text = text

  fun has_next(): Bool =>
    _at < _text.size()

  fun ref next(): String val =>
    let start = _at
    _at =
      try
        _text.find("\n", start.isize())?.usize() + 1
      else
        _text.size()
      end
    _text.trim(start, _at)
