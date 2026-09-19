class _TokenStream
  """
  A source and the tokens that cover it, scanned as far as asked.

  Lossless: every byte of `source` lies in exactly one token, so
  concatenating each token's text reproduces the source. Whitespace and
  comments are tokens like any other.

  Error-tolerant: no input fails to produce a stream. Bytes that cannot be
  interpreted become `TkLexError` tokens and scanning continues: a byte
  that starts no token is one `TkLexError` of one byte, a literal or
  comment that does not terminate is one to the end of the source, and
  a refused number, character literal or triple-quoted string is one
  over the bytes ponyc's lexer read before refusing it. Each refusal is
  also in the failure list, in token order, with the escapes refused
  inside a literal that kept its kind; `next_failure` and
  `take_failure` read the list as a cursor.

  `token(i)` scans forward until token `i` exists and returns it; at and
  past the end it is `(TkEof, 0)`. There is no size, so nothing can force
  the rest of the source by accident.

  Tokens carry a width and not an offset, so an edit changes only the tokens
  it touches. A consumer that needs offsets accumulates them while walking;
  `values()` does this.
  """
  let source: String val
  let _symbols: Array[(String val, TokenKind)] val = _Symbols()
  embed _tokens: Array[(TokenKind, U32)] = Array[(TokenKind, U32)]
  embed _failures: Array[(USize, LexFailure, USize, USize)] =
    Array[(USize, LexFailure, USize, USize)]
  var _next_failure: USize = 0
  var _at: USize = 0
    """
    The byte offset the next scan starts at.
    """
  var _after_newline: Bool = true
    """
    ponyc's `newline` flag: whether `(`, `[` and `-` take their newline
    form. True at the start of the source and after a whitespace run
    holding a newline; a line comment or a whitespace run without one
    leaves it; every other token clears it.
    """
  var _done: Bool = false

  new create(source': String val) =>
    source = source'

  fun ref token(i: USize): (TokenKind, U32) =>
    """
    The kind and width of token `i`, scanning as far as needed to reach
    it; `(TkEof, 0)` at and past the end.
    """
    while (_tokens.size() <= i) and (not _done) do
      _scan_one()
    end
    try _tokens(i)? else (TkEof, 0) end

  fun ref next_failure(): ((USize, LexFailure, USize, USize) | None) =>
    """
    The next refusal the cursor has not passed, as `(token index,
    failure, offset, length)`, or `None` when there is none among the
    tokens scanned so far.
    """
    try _failures(_next_failure)? else None end

  fun ref take_failure() =>
    """
    Passes the cursor over the refusal `next_failure` returned; nothing
    when it returned `None`.
    """
    if _next_failure < _failures.size() then
      _next_failure = _next_failure + 1
    end

  fun _scanned(): USize =>
    """
    How many tokens have been scanned, the final `TkEof` not counted.
    """
    _tokens.size()

  fun ref values(): _TokenIterator^ =>
    """
    Every token as `(kind, offset, width)`, with offsets accumulated as the
    walk proceeds, ending with the `TkEof`.
    """
    _TokenIterator._create(this)

  fun _byte(i: USize): U8 =>
    """
    The byte at `i`, or 0 past the end. Zero is not a byte any Pony source
    construct starts with, so callers may look ahead without bounds checks.
    """
    try source(i)? else 0 end

  fun tag _is_space(c: U8): Bool =>
    (c == ' ') or (c == '\t') or (c == '\r') or (c == '\n')

  fun tag _is_digit(c: U8): Bool =>
    (c >= '0') and (c <= '9')

  fun tag _is_ident_start(c: U8): Bool =>
    ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or (c == '_')

  fun tag _is_ident(c: U8): Bool =>
    _is_ident_start(c) or _is_digit(c) or (c == '\'')

  fun ref _push(kind: TokenKind, from: USize, to: USize) =>
    _tokens.push((kind, (to - from).u32()))

  fun ref _refuse(failure: LexFailure, from: USize, to: USize) =>
    _failures.push((_tokens.size(), failure, from, to - from))
    _push(TkLexError, from, to)

  fun ref _scan_one() =>
    """
    One step of ponyc's `lexer_next` loop, with trivia emitted rather than
    skipped: the token at `_at`, or the end.

    A nested comment clears `_after_newline`, so that a newline inside a
    comment does not reach symbol disambiguation.
    """
    let n = source.size()
    let i = _at
    if i >= n then
      _done = true
      return
    end
    let c = _byte(i)

    if _is_space(c) then
      (let j, let saw_newline) = _space(i, n)
      _push(TkWhitespace, i, j)
      if saw_newline then _after_newline = true end
      _at = j
    elseif (c == '/') and (_byte(i + 1) == '/') then
      let j = _line_comment(i, n)
      _push(TkLineComment, i, j)
      _at = j
    elseif (c == '/') and (_byte(i + 1) == '*') then
      (let j, let terminated) = _nested_comment(i, n)
      if terminated then
        _push(TkNestedComment, i, j)
      else
        _refuse(UnterminatedComment, i, j)
      end
      _after_newline = false
      _at = j
    else
      (let kind, let j, let failure) = _token(i, n, _after_newline)
      match failure
      | let f: LexFailure => _refuse(f, i, j)
      | None => _push(kind, i, j)
      end
      _after_newline = false
      _at = j
    end

  fun _space(from: USize, n: USize): (USize, Bool) =>
    """
    A maximal run of whitespace, and whether it contains a real newline.
    """
    var j = from
    var saw_newline = false
    while j < n do
      let c = _byte(j)
      if not _is_space(c) then break end
      if c == '\n' then saw_newline = true end
      j = j + 1
    end
    (j, saw_newline)

  fun _line_comment(from: USize, n: USize): USize =>
    """
    A `//` comment, up to but not including the newline that ends it. The
    newline is whitespace and belongs to the next token.
    """
    var j = from + 2
    while (j < n) and (_byte(j) != '\n') do
      j = j + 1
    end
    j

  fun _nested_comment(from: USize, n: USize): (USize, Bool) =>
    """
    A `/* */` comment, which may contain further `/* */` pairs, and
    whether it terminated. An unterminated one runs to the end of the
    source rather than failing.
    """
    var j = from + 2
    var depth: USize = 1
    while (j < n) and (depth > 0) do
      if (_byte(j) == '*') and (_byte(j + 1) == '/') then
        depth = depth - 1
        j = j + 2
      elseif (_byte(j) == '/') and (_byte(j + 1) == '*') then
        depth = depth + 1
        j = j + 2
      else
        j = j + 1
      end
    end
    (j, depth == 0)

  fun ref _token(from: USize, n: USize, after_newline: Bool)
    : (TokenKind, USize, (LexFailure | None))
  =>
    """
    One non-trivia token: its kind, where it ends, and why it was
    refused when it was.
    """
    let c = _byte(from)

    if c == '"' then
      _string(from, n)
    elseif c == '\'' then
      _character(from, n)
    elseif c == '#' then
      _hash(from, n)
    elseif _is_digit(c) then
      _number(from)
    elseif _is_ident_start(c) then
      _identifier(from, n)
    else
      _symbol(from, n, after_newline)
    end

  fun _identifier(from: USize, n: USize): (TokenKind, USize, None) =>
    """
    An identifier, or the keyword it spells. Pony allows a trailing prime,
    so `x'` and `x''` are identifiers.
    """
    var j = from
    while (j < n) and _is_ident(_byte(j)) do
      j = j + 1
    end
    let word = source.substring(from.isize(), j.isize())
    match _Keywords(consume word)
    | let k: TokenKind => (k, j, None)
    else
      (TkId, j, None)
    end

  fun _hash(from: USize, n: USize): (TokenKind, USize, None) =>
    """
    A generic capability -- `#read`, `#send`, `#share`, `#alias`, `#any` --
    or a bare `#`, which is `TkConstant`.
    """
    var j = from + 1
    while (j < n) and _is_ident(_byte(j)) do
      j = j + 1
    end
    let word = source.substring(from.isize(), j.isize())
    match _Keywords(consume word)
    | let k: TokenKind => (k, j, None)
    else
      (TkConstant, from + 1, None)
    end

  fun _symbol(from: USize, n: USize, after_newline: Bool)
    : (TokenKind, USize, (UnrecognizedCharacter | None))
  =>
    """
    The longest symbol that matches here, in its newline form where it has
    one. A byte that starts no symbol is one `TkLexError`, so that scanning
    continues rather than stopping at the first bad character.
    """
    for (text, kind) in _symbols.values() do
      if source.at(text, from.isize()) then
        return (_NewlineForm(kind, after_newline), from + text.size(), None)
      end
    end
    (TkLexError, from + 1, UnrecognizedCharacter(_byte(from)))

  fun ref _fail_inside(failure: LexFailure, from: USize, to: USize) =>
    """
    Record a refusal inside the token being scanned, which keeps its
    kind: an escape in a literal.
    """
    _failures.push((_tokens.size(), failure, from, to - from))

  fun _number(from: USize): (TokenKind, USize, (LexFailure | None)) =>
    """
    An integer or a float, ponyc's `number`, `lex_integer` and `real`:
    a refused literal ends where ponyc's lexer stopped reading it, and
    the bytes after that are the next token's.

    A `.` begins a fraction only when a digit follows it, so that
    `1.string()` is an integer, a dot and a method name; an `e` after
    the digits always begins an exponent, so `1e` is refused as ponyc
    refuses it.
    """
    if (_byte(from) == '0') and
      ((_byte(from + 1) == 'x') or (_byte(from + 1) == 'X'))
    then
      return _integer_token(from + 2, 16, HexadecimalNumber, false)
    end
    if (_byte(from) == '0') and
      ((_byte(from + 1) == 'b') or (_byte(from + 1) == 'B'))
    then
      return _integer_token(from + 2, 2, BinaryNumber, false)
    end

    (let after_digits, let failure) = _integer(from, 10, DecimalNumber, true)
    match failure
    | let f: LexFailure => return (TkLexError, after_digits, f)
    end
    var j = after_digits
    var kind: TokenKind = TkInt

    if _byte(j) == '.' then
      if not _is_digit(_byte(j + 1)) then
        return (TkInt, j, None)
      end
      kind = TkFloat
      (let after_mantissa, let mantissa) =
        _integer(j + 1, 10, RealMantissa, true)
      j = after_mantissa
      match mantissa
      | let f: LexFailure => return (TkLexError, j, f)
      end
    end

    if (_byte(j) == 'e') or (_byte(j) == 'E') then
      kind = TkFloat
      j = j + 1
      if (_byte(j) == '+') or (_byte(j) == '-') then
        j = j + 1
      end
      (let after_exponent, let exponent) =
        _integer(j, 10, RealExponent, false)
      j = after_exponent
      match exponent
      | let f: LexFailure => return (TkLexError, j, f)
      end
    end

    (kind, j, None)

  fun _integer_token(from: USize, base: U128, context: NumberContext,
    end_on_e: Bool): (TokenKind, USize, (LexFailure | None))
  =>
    (let j, let failure) = _integer(from, base, context, end_on_e)
    match failure
    | let f: LexFailure => (TkLexError, j, f)
    | None => (TkInt, j, None)
    end

  fun _integer(from: USize, base: U128, context: NumberContext,
    end_on_e: Bool): (USize, (LexFailure | None))
  =>
    """
    ponyc's `lex_integer`: digits of `base` with single underscores
    between them, accumulated as a `U128` so that overflow is refused
    where ponyc refuses it. Returns the offset of the first byte ponyc's
    lexer would not have consumed, and the refusal when there is one.
    """
    var j = from
    var value: U128 = 0
    var digits: USize = 0
    var previous_underscore = false
    while true do
      let c = _byte(j)
      if c == '_' then
        if previous_underscore then
          return (j, DuplicateUnderscore(context))
        end
        previous_underscore = true
        j = j + 1
        continue
      end
      if end_on_e and ((c == 'e') or (c == 'E')) then
        break
      end
      let digit: U128 =
        if _is_digit(c) then (c - '0').u128()
        elseif (c >= 'a') and (c <= 'z') then ((c - 'a') + 10).u128()
        elseif (c >= 'A') and (c <= 'Z') then ((c - 'A') + 10).u128()
        else break
        end
      if digit >= base then
        return (j, InvalidDigit(context, c))
      end
      (let scaled, let overflow) = value.mulc(base)
      (let next, let carried) = scaled.addc(digit)
      if overflow or carried then
        return (j, NumericOverflow)
      end
      value = next
      previous_underscore = false
      j = j + 1
      digits = digits + 1
    end
    if digits == 0 then
      return (j, NoDigits(context))
    end
    if previous_underscore then
      return (j, TrailingUnderscore(context))
    end
    (j, None)

  fun ref _string(from: USize, n: USize)
    : (TokenKind, USize, (LexFailure | None))
  =>
    """
    A string literal, either triple-quoted or single-quoted. An
    unterminated one is a `TkLexError` covering what remains, which is
    ponyc's verdict; it runs to the end of the source rather than
    failing. A bad escape is recorded where it sits and the literal
    keeps its kind.
    """
    if source.at("\"\"\"", from.isize()) then
      return _triple_string(from, n)
    end

    var j = from + 1
    while j < n do
      let c = _byte(j)
      if c == '\\' then
        j = _escape(j, true, true)
      elseif c == '"' then
        return (TkString, j + 1, None)
      else
        // A raw newline is allowed. ponyc's `string` scans to the closing
        // quote or to the end of the source and checks for nothing else,
        // and `files/_non_root_test.pony` relies on it.
        j = j + 1
      end
    end
    (TkLexError, n, UnterminatedLiteral)

  fun _triple_string(from: USize, n: USize)
    : (TokenKind, USize, (LexFailure | None))
  =>
    """
    ponyc's `triple_string`: no escapes; a literal of more than one
    line may have nothing but whitespace after the opening quotes on
    their line.
    """
    var j = from + 3
    var non_space_on_first_line = false
    var first_line = true
    while j < n do
      if source.at("\"\"\"", j.isize()) then
        j = j + 3
        // A run of more than three quotes closes at the last of them.
        while (j < n) and (_byte(j) == '"') do
          j = j + 1
        end
        if (not first_line) and non_space_on_first_line then
          return (TkLexError, j, TripleQuoteNotBelowOpener)
        end
        return (TkString, j, None)
      end
      let c = _byte(j)
      if c == '\n' then
        first_line = false
      elseif first_line and (not _is_c_space(c)) then
        non_space_on_first_line = true
      end
      j = j + 1
    end
    (TkLexError, n, UnterminatedLiteral)

  fun tag _is_c_space(c: U8): Bool =>
    """
    C's `isspace`: the four bytes `_is_space` holds, and `\v` and `\f`.
    """
    _is_space(c) or (c == 0x0B) or (c == 0x0C)

  fun ref _character(from: USize, n: USize)
    : (TokenKind, USize, (LexFailure | None))
  =>
    """
    A character literal, which ponyc lexes as an integer. An empty one
    is refused; a bad escape is recorded where it sits and the literal
    stays an integer.
    """
    var j = from + 1
    var chars: USize = 0
    while j < n do
      let c = _byte(j)
      if c == '\\' then
        j = _escape(j, false, false)
      elseif c == '\'' then
        if chars == 0 then
          return (TkLexError, j + 1, EmptyCharacterLiteral)
        end
        return (TkInt, j + 1, None)
      else
        j = j + 1
      end
      chars = chars + 1
    end
    (TkLexError, n, UnterminatedLiteral)

  fun ref _escape(from: USize, unicode_allowed: Bool, is_string: Bool)
    : USize
  =>
    """
    ponyc's `escape`: the sequence starting at the `\` at `from`,
    recorded as refused when it is one ponyc refuses, positioned at the
    `\` and covering what ponyc read of it. Returns where the sequence
    ends. Reading past the end of the source is safe: `_byte` is 0
    there, which no escape accepts.
    """
    let c = _byte(from + 1)
    var j = from + 2
    var hex_digits: USize = 0
    var known = true
    match c
    | 'a' | 'b' | 'e' | 'f' | 'n' | 'r' | 't' | 'v' | '\\' | '0' => None
    | 'x' => hex_digits = 2
    | '"' => known = is_string
    | '\'' => known = not is_string
    | 'u' => if unicode_allowed then hex_digits = 4 else known = false end
    | 'U' => if unicode_allowed then hex_digits = 6 else known = false end
    else
      known = false
    end
    if hex_digits > 0 then
      var value: U32 = 0
      var read: USize = 0
      while read < hex_digits do
        let d = _byte(j)
        let digit: U32 =
          if _is_digit(d) then (d - '0').u32()
          elseif (d >= 'a') and (d <= 'f') then ((d - 'a') + 10).u32()
          elseif (d >= 'A') and (d <= 'F') then ((d - 'A') + 10).u32()
          else break
          end
        value = (value << 4) + digit
        j = j + 1
        read = read + 1
      end
      if read < hex_digits then
        _fail_inside(InvalidEscape(_text(from, j),
          HexDigitsRequired(hex_digits)), from, j.min(source.size()))
      elseif value > 0x10FFFF then
        _fail_inside(InvalidEscape(_text(from, j), ExceedsUnicodeRange),
          from, j.min(source.size()))
      end
    elseif not known then
      _fail_inside(InvalidEscape(_text(from, j), UnknownEscape), from,
        j.min(source.size()))
    end
    j

  fun _text(from: USize, to: USize): String val =>
    """
    The source bytes from `from` to `to`, clipped to the source.
    """
    source.substring(from.isize(), to.min(source.size()).isize())

class _TokenIterator is Iterator[(TokenKind, USize, USize)]
  """
  Walks a token stream, accumulating the offset that the tokens' widths
  imply. The final `TkEof` is the last item.
  """
  let _stream: _TokenStream ref
  var _index: USize = 0
  var _offset: USize = 0
  var _ended: Bool = false

  new _create(stream: _TokenStream ref) =>
    _stream = stream

  fun has_next(): Bool =>
    not _ended

  fun ref next(): (TokenKind, USize, USize) =>
    (let kind, let width) = _stream.token(_index)
    let offset = _offset
    _index = _index + 1
    _offset = _offset + width.usize()
    if kind is TkEof then _ended = true end
    (kind, offset, width.usize())
