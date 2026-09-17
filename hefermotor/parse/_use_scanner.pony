use diag = "../diagnostics"
use source = "../source"

class _UseScanner
  """
  Reads a file's `use` section line by line. The package docstring is the
  module's first token, so after leading `//` comments and blank lines a
  line that opens a string literal is skipped to the literal's close. Then
  each line whose first token is `use` is read as declarations, as many
  as the line holds, and every other line is skipped, until a line whose
  first token opens a type definition (`type`, `interface`, `trait`,
  `primitive`, `struct`, `class`, `actor`) ends the section. It reports
  nothing: a `use` that does not fit `use [alias =] "locator" [if guard]`
  is skipped.

  The scanner reads a declaration from its line, and a guard from the
  line after `if` when `if` ends a line, so a `use` whose string literal
  sits on the line after `use` is not found. `/* */` comments are read as
  code: one before the docstring leaves the docstring unskipped, one
  holding a type keyword as a line's first token ends the section, and
  one on a `use` line is part of what it sits in. Only `\"` and `\\` are
  decoded in a locator.
  """
  let _file: source.SourceFile
  let _text: String
  var _pos: USize = 0

  new create(file: source.SourceFile) =>
    _file = file
    _text = file.content

  fun ref run(): Array[UseDecl] val =>
    let uses = recover iso Array[UseDecl] end
    let use_keyword: USize = "use".size()
    _skip_blank_and_comments()
    _skip_docstring()
    while _pos < _text.size() do
      let line_start = _pos
      let line_end = _line_end(line_start)
      _pos = _next_line(line_end)
      let first = _first_token(line_start, line_end)
      if first == "use" then
        var at = _skip_spaces(line_start)
        while (at < line_end) and (_first_token(at, line_end) == "use") do
          (let decl, let next) = _read_use(at, line_end, use_keyword)
          match decl
          | let u: UseDecl => uses.push(u)
          | None => None
          end
          if next <= at then break end
          at = _skip_spaces(next)
        end
      elseif _opens_type(first) then
        break
      end
    end
    consume uses

  fun ref _skip_blank_and_comments() =>
    """
    Advances past lines that are empty or hold only a `//` comment.
    """
    while _pos < _text.size() do
      let line_end = _line_end(_pos)
      let content = _skip_spaces(_pos)
      let blank = content >= line_end
      if not (blank or _text.at("//", content.isize())) then return end
      _pos = _next_line(line_end)
    end

  fun ref _skip_docstring() =>
    let start = _skip_spaces(_pos)
    if _text.at("\"\"\"", start.isize()) then
      _pos = _after_delimiter("\"\"\"", start + 3)
    elseif _text.at("\"", start.isize()) then
      _pos = _after_delimiter("\"", start + 1)
    end

  fun _after_delimiter(delimiter: String, from: USize): USize =>
    """
    The offset just past the next occurrence of `delimiter` at or after
    `from`, skipping a backslash-escaped character when `delimiter` is
    `"`; the end of the text if there is none.
    """
    var i = from
    while i < _text.size() do
      if _text.at(delimiter, i.isize()) then
        return i + delimiter.size()
      end
      try
        if (delimiter == "\"") and (_text(i)? == '\\') then i = i + 1 end
      else
        _Unreachable()
      end
      i = i + 1
    end
    _text.size()

  fun _opens_type(first: String): Bool =>
    (first == "type") or (first == "interface") or (first == "trait")
      or (first == "primitive") or (first == "struct")
      or (first == "class") or (first == "actor")

  fun ref _read_use(use_start: USize, line_end: USize, keyword: USize)
    : ((UseDecl | None), USize)
  =>
    """
    One `use [alias =] "locator" [if guard]` starting at `use_start`, and
    the offset just past it. `None` for `use @...` and for anything that
    does not fit that shape: an alias with no `=`, an empty alias, no
    literal, a literal that does not close on the line, or a
    triple-quoted literal. A guard runs to a `//` comment, to the next
    `use`, or to the end of its line, trailing blanks dropped; when `if`
    ends the line, the guard is the next line.
    """
    var i = _skip_spaces(use_start + keyword)
    if (i < line_end) and (_byte(i) == '@') then return (None, line_end) end
    var alias: (String | None) = None
    if (i < line_end) and (_byte(i) != '"') then
      let name_start = i
      while (i < line_end) and _is_ident(_byte(i)) do i = i + 1 end
      if i == name_start then return (None, line_end) end
      let name: String = _text.substring(name_start.isize(), i.isize())
      i = _skip_spaces(i)
      if (i >= line_end) or (_byte(i) != '=') then
        return (None, line_end)
      end
      alias = name
      i = _skip_spaces(i + 1)
    end
    if (i >= line_end) or (_byte(i) != '"') then return (None, line_end) end
    if _text.at("\"\"\"", i.isize()) then return (None, line_end) end
    let literal_start = i
    (let locator, let literal_end) = _read_literal(i + 1, line_end)
    if literal_end > line_end then return (None, line_end) end
    var span_end = literal_end
    var guard: (diag.Span | None) = None
    let after = _skip_spaces(literal_end)
    if _text.at("if", after.isize())
      and (((after + 2) >= line_end) or (not _is_ident(_byte(after + 2))))
    then
      var guard_start = _skip_spaces(after + 2)
      var guard_line_end = line_end
      if guard_start >= line_end then
        // `if` ends the line: the guard is the next line, which the
        // caller must not read again.
        guard_start = _skip_spaces(_next_line(line_end))
        guard_line_end = _line_end(guard_start)
        _pos = _next_line(guard_line_end)
      end
      let guard_end = _trim_end(guard_start,
        _guard_end(guard_start, guard_line_end))
      guard = _span(guard_start, guard_end)
      span_end = guard_end
    end
    (UseDecl(locator, alias, guard, _span(use_start, span_end),
      _span(literal_start, literal_end)), span_end)

  fun _read_literal(from: USize, line_end: USize): (String, USize) =>
    """
    The decoded content of the string literal whose opening quote precedes
    `from`, and the offset just past its closing quote; the offset is past
    `line_end` when the literal does not close on the line.
    """
    let out = recover iso String end
    var i = from
    while i < line_end do
      try
        let c = _text(i)?
        if c == '"' then
          return (consume out, i + 1)
        elseif (c == '\\') and ((i + 1) < line_end) then
          let e = _text(i + 1)?
          if (e == '"') or (e == '\\') then
            out.push(e)
            i = i + 2
            continue
          end
        end
        out.push(c)
      else
        _Unreachable()
      end
      i = i + 1
    end
    (consume out, line_end + 1)

  fun _byte(i: USize): U8 =>
    """
    The byte at `i`; `i` must be below the text's size.
    """
    try _text(i)? else _Unreachable(); 0 end

  fun _is_blank(c: U8): Bool =>
    (c == ' ') or (c == '\t') or (c == '\r')

  fun _guard_end(from: USize, line_end: USize): USize =>
    """
    Where a guard starting at `from` ends: at a `//` comment, at the next
    `use` token, or at `line_end`.
    """
    var i = from
    while i < line_end do
      if _text.at("//", i.isize()) then return i end
      if (i > from) and _is_blank(_byte(i - 1))
        and (_first_token(i, line_end) == "use")
      then
        return i
      end
      i = i + 1
    end
    line_end

  fun _span(start: USize, finish: USize): diag.Span =>
    diag.Span(_file.dir, _file.name, start, finish - start)

  fun _first_token(from: USize, line_end: USize): String =>
    let start = _skip_spaces(from)
    var i = start
    if _text.at("//", start.isize()) then return "//" end
    try
      while (i < line_end) and _is_ident(_text(i)?) do i = i + 1 end
    else
      _Unreachable()
    end
    _text.substring(start.isize(), i.isize())

  fun _is_ident(c: U8): Bool =>
    ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))
      or ((c >= '0') and (c <= '9')) or (c == '_')

  fun _skip_spaces(from: USize): USize =>
    var i = from
    while (i < _text.size()) and _is_blank(_byte(i)) do i = i + 1 end
    i

  fun _trim_end(from: USize, line_end: USize): USize =>
    var i = line_end
    while (i > from) and _is_blank(_byte(i - 1)) do i = i - 1 end
    i

  fun _line_end(from: USize): USize =>
    """
    The offset of the line's `\n`, or of the `\r` before it, or the end
    of the text.
    """
    var i = from
    try
      while (i < _text.size()) and (_text(i)? != '\n') do i = i + 1 end
      if (i > from) and (_text(i - 1)? == '\r') then i = i - 1 end
    else
      _Unreachable()
    end
    i

  fun _next_line(line_end: USize): USize =>
    var i = line_end
    try
      while (i < _text.size()) and (_text(i)? != '\n') do i = i + 1 end
    else
      _Unreachable()
    end
    i + 1
