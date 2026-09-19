use "pony_test"

primitive \nodoc\ _LexDiagnosticTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestLexFailureFamily)
    test(_TestLexRefusedExtents)
    test(_TestLexEscapeRecords)
    test(_TestLexOverflowBoundary)
    test(_TestLexByteRendering)
    test(_TestLexBesideParse)
    test(_TestStringLiteralValue)
    test(_TestStringLiteralTriple)

class \nodoc\ iso _TestLexFailureFamily is UnitTest
  fun name(): String =>
    "parse/lex: one record per failure, at ponyc's position"

  fun apply(h: TestHelper) =>
    """
    One case per lexer refusal ponyc reports: exactly one `parse/lex`
    where `ponyc --pass=parse` reports it, with ponyc's text. A refused
    number, character literal or `$` leaves the assignment's right side
    a refused token, which the parser does not report on top.
    """
    let cases: Array[(String val, USize, String val)] val = [
      ("let x = 1__2", 8, "Invalid duplicate underscore in decimal number")
      ("let x = \"\\q\"", 9, "Invalid escape sequence \"\\q\"")
      ("let x = '\\q'", 9, "Invalid escape sequence \"\\q\"")
      ("let x = ''", 8, "Empty character literal")
      ("let x = 0x", 8, "No digits in hexadecimal number")
      ("let x = 1_", 8,
        "Numeric literal cannot end with underscore in decimal number")
      ("let x = 0b2", 8, "Invalid character in binary number: 2")
      ("let x = 1a", 8, "Invalid character in decimal number: a")
      ("let x = 1e", 8, "No digits in real number exponent")
      ("let x = 1.5e", 8, "No digits in real number exponent")
      ("let x = 1.5_", 8,
        "Numeric literal cannot end with underscore in real number mantissa")
      ("let x = 1.5a", 8, "Invalid character in real number mantissa: a")
      ("let x = \"\\xZ1\"", 9,
        "Invalid escape sequence \"\\x\", 2 hex digits required")
      ("let x = \"\\x1Z\"", 9,
        "Invalid escape sequence \"\\x1\", 2 hex digits required")
      ("let x = '\\u0041'", 9, "Invalid escape sequence \"\\u\"")
      ("let x = \"\\'\"", 9, "Invalid escape sequence \"\\'\"")
      ("let x = \"\\U110000\"", 9,
        "Escape sequence \"\\U110000\" exceeds unicode range (0x10FFFF)")
      ("let x = \"abc", 8, "Literal doesn't terminate")
      ("let x = 'a", 8, "Literal doesn't terminate")
      ("let x = /* abc", 8, "Nested comment doesn't terminate")
      ("let x = \"\"\"abc\n    def\"\"\"", 8,
        "multi-line triple-quoted string must be started below the " +
        "opening triple-quote")
      ("let x = $", 8, "Unrecognized character: $")
      ("let x = 1\x1b", 9, "Unrecognized character: \\x1b")
    ]
    for (body, position, message) in cases.values() do
      _Exactly(h, _Nested.body(body),
        [("parse/lex", 41 + position, message)], body)
    end
    _Exactly(h, _Nested.body("let x = " + String.from_array([0xEF])),
      [("parse/lex", 49, "Unrecognized character: \\xef")], "a lone lead byte")
    // Two escapes refused in one literal, then a refused token after
    // it: every record reaches the report. ponyc: 3:14, 3:16, 3:22.
    _Exactly(h, _Nested.body("let x = \"\\q\\p\" + $"), [
      ("parse/lex", 50, "Invalid escape sequence \"\\q\"")
      ("parse/lex", 52, "Invalid escape sequence \"\\p\"")
      ("parse/lex", 58, "Unrecognized character: $")
    ], "two escapes and a token")
    // A `\` as the source's last byte: the escape and the unterminated
    // literal, where a ponyc built with assertions aborts.
    _Exactly(h, "actor Main\n  new create(env: Env) =>\n    \"abc\\", [
      ("parse/lex", 41, "Literal doesn't terminate")
      ("parse/lex", 45, "Invalid escape sequence \"\\\"")
    ], "a backslash last")

class \nodoc\ iso _TestLexRefusedExtents is UnitTest
  fun name(): String => "parse/lex: a refused number ends where ponyc stopped"

  fun apply(h: TestHelper) =>
    """
    A refused numeric literal covers the bytes ponyc's lexer consumed
    before refusing it, and scanning goes on from there: `1__2` is a
    refused `1_` and an identifier `_2`; `0b2` a refused `0b` and an
    integer `2`; `1a` a refused `1` and an identifier `a`; `1_` and
    `0x` are refused whole. A refused escape leaves its literal a
    string or an integer covering the whole literal.
    """
    _kinds(h, "1__2", "TkLexError:2 TkId:2")
    _kinds(h, "0b2", "TkLexError:2 TkInt:1")
    _kinds(h, "1a", "TkLexError:1 TkId:1")
    _kinds(h, "1_", "TkLexError:2")
    _kinds(h, "0x", "TkLexError:2")
    _kinds(h, "1e", "TkLexError:2")
    _kinds(h, "340282366920938463463374607431768211456",
      "TkLexError:38 TkInt:1")
    _kinds(h, "''", "TkLexError:2")
    _kinds(h, "\"\\q\"", "TkString:4")
    _kinds(h, "'\\q'", "TkInt:4")
    _kinds(h, "\"\"\"a\nb\"\"\"", "TkLexError:9")

  fun _kinds(h: TestHelper, src: String val, expected: String) =>
    let out = recover iso String end
    for (kind, _, width) in _TokenStream(src).values() do
      if kind is TkEof then break end
      if out.size() > 0 then out.push(' ') end
      out.append(kind.name())
      out.push(':')
      out.append(width.string())
    end
    h.assert_eq[String](expected, consume out, src)

class \nodoc\ iso _TestLexEscapeRecords is UnitTest
  fun name(): String => "parse/lex: an escape record covers what ponyc read"

  fun apply(h: TestHelper) =>
    """
    The failure list's escape record starts at the `\` and covers the
    escape as ponyc read it: two bytes for an unknown one, `\x` and the
    digits read for a short hex one, all eight for one out of range,
    and one byte for a `\` that ends the source.
    """
    _record(h, "\"\\q\"", 1, 2)
    _record(h, "\"\\x1Z\"", 1, 3)
    _record(h, "\"\\U110000\"", 1, 8)
    _record(h, "\"\\", 1, 1)

  fun _record(h: TestHelper, src: String val, at: USize, length: USize) =>
    let stream = _TokenStream(src)
    stream.token(0)
    match stream.next_failure()
    | (_, let f: InvalidEscape, let start: USize, let len: USize) =>
      h.assert_eq[USize](at, start, src + ": start")
      h.assert_eq[USize](length, len, src + ": length")
    else
      h.fail(src + ": no escape record")
    end

class \nodoc\ iso _TestLexOverflowBoundary is UnitTest
  fun name(): String => "parse/lex: overflow at ponyc's threshold"

  fun apply(h: TestHelper) =>
    """
    `U128.max_value()` is accepted and one more is refused, in decimal,
    hexadecimal and binary, as ponyc's `lexint_accum` refuses it.
    """
    let max: String val = "340282366920938463463374607431768211455"
    let over: String val = "340282366920938463463374607431768211456"
    let hex_max: String val = "0x" + "f".mul(32)
    let hex_over: String val = "0x1" + "0".mul(32)
    let bin_max: String val = "0b" + "1".mul(128)
    let bin_over: String val = "0b1" + "0".mul(128)
    for accepted in [max; hex_max; bin_max].values() do
      _Exactly(h, _Nested.body("let x = " + accepted), [], accepted)
    end
    for refused in [over; hex_over; bin_over].values() do
      _Exactly(h, _Nested.body("let x = " + refused),
        [("parse/lex", 49, "overflow in numeric literal")], refused)
    end

class \nodoc\ iso _TestLexByteRendering is UnitTest
  fun name(): String => "parse/lex: a source byte renders printable"

  fun apply(h: TestHelper) =>
    """
    The three members that carry source bytes render a printable ASCII
    byte as itself and any other as `\xNN`, so a message never holds a
    control character or a lone lead byte.
    """
    h.assert_eq[String]("Unrecognized character: $",
      UnrecognizedCharacter('$').message())
    h.assert_eq[String]("Unrecognized character: \\xef",
      UnrecognizedCharacter(0xEF).message())
    h.assert_eq[String]("Invalid character in decimal number: z",
      InvalidDigit(DecimalNumber, 'z').message())
    h.assert_eq[String]("Invalid character in decimal number: \\x1b",
      InvalidDigit(DecimalNumber, 0x1B).message())
    h.assert_eq[String]("Invalid escape sequence \"\\q\"",
      InvalidEscape("\\q", UnknownEscape).message())
    h.assert_eq[String]("Invalid escape sequence \"\\\\x1b\"",
      InvalidEscape("\\\x1b", UnknownEscape).message())
    h.assert_eq[String]("Invalid escape sequence \"\\ \"",
      InvalidEscape("\\ ", UnknownEscape).message())
    h.assert_eq[String]("Invalid escape sequence \"\\~\"",
      InvalidEscape("\\~", UnknownEscape).message())
    h.assert_eq[String]("Invalid escape sequence \"\\\\x7f\"",
      InvalidEscape("\\\x7f", UnknownEscape).message())
    h.assert_eq[String]("Unrecognized character: \\x1f",
      UnrecognizedCharacter(0x1F).message())
    h.assert_eq[String](
      "Invalid escape sequence \"\\u\", 4 hex digits required",
      InvalidEscape("\\u", HexDigitsRequired(4)).message())
    h.assert_eq[String](
      "Escape sequence \"\\U110000\" exceeds unicode range (0x10FFFF)",
      InvalidEscape("\\U110000", ExceedsUnicodeRange).message())

class \nodoc\ iso _TestLexBesideParse is UnitTest
  fun name(): String => "parse/lex: lexer records sort with the parser's"

  fun apply(h: TestHelper) =>
    """
    A lexer record before a parser record in one file sorts first, and
    an escape refused inside an unclosed `if` is recorded at the escape
    beside the `if` at its opener, as ponyc reports both: `4:8:
    Invalid escape sequence "\q"` and `3:5: syntax error: unterminated
    if expression`.
    """
    _Exactly(h, "class C\n  fun f() => $\n  fun g() => x =\n", [
      ("parse/lex", 21, "Unrecognized character: $")
      ("parse/expected", 38, "syntax error: expected assign rhs, found " +
        "the end of the file")
    ], "lexer first")
    _Exactly(h, "actor Main\n  new create(env: Env) =>\n" +
      "    if true then\n      \"\\q\"\n", [
      ("parse/unterminated", 41, "syntax error: unterminated if expression")
      ("parse/lex", 61, "Invalid escape sequence \"\\q\"")
    ], "escape inside an open if")

class \nodoc\ iso _TestStringLiteralValue is UnitTest
  fun name(): String => "parse/string literal: the value of a quoted literal"

  fun apply(h: TestHelper) =>
    """
    Escapes decode as ponyc's lexer decodes them: a hex escape is its
    code point in UTF-8 form, a surrogate as its own bytes, a refused
    escape drops out of the value, and text that is no string literal
    is returned as it is. `of` reads a node's text the same way.
    """
    h.assert_eq[String]("a\tb\n", StringLiteralValue("\"a\\tb\\n\""))
    h.assert_eq[String]("\a\b\e\f\r\v\0",
      StringLiteralValue("\"\\a\\b\\e\\f\\r\\v\\0\""))
    h.assert_eq[String]("aZ", StringLiteralValue("\"a\\x1Z\""))
    h.assert_eq[String](String.from_array([0xED; 0xA0; 0x80]),
      StringLiteralValue("\"\\uD800\""))
    h.assert_eq[String]("\"\\", StringLiteralValue("\"\\\"\\\\\""))
    h.assert_eq[String]("\u00EF", StringLiteralValue("\"\\xEF\""))
    h.assert_eq[String]("A\u00E9", StringLiteralValue("\"\\u0041\\u00e9\""))
    h.assert_eq[String]("\U01F600", StringLiteralValue("\"\\U01F600\""))
    h.assert_eq[String]("ab", StringLiteralValue("\"a\\qb\""))
    h.assert_eq[String]("ab", StringLiteralValue("\"a\\'b\""))
    h.assert_eq[String]("aZ1", StringLiteralValue("\"a\\xZ1\""))
    h.assert_eq[String]("a", StringLiteralValue("\"a\\U110000\""))
    h.assert_eq[String]("42", StringLiteralValue("42"))
    h.assert_eq[String]("", StringLiteralValue("\"\""))
    let tree = _ParseText("class C\n  let x: String = \"a\\tb\"\n")
    for n in tree.nodes() do
      if n.kind() is TkString then
        h.assert_eq[String]("a\tb", StringLiteralValue.of(n))
      end
    end

class \nodoc\ iso _TestStringLiteralTriple is UnitTest
  fun name(): String => "parse/string literal: normalise_string"

  fun apply(h: TestHelper) =>
    """
    ponyc's `lexer.cc` triple-string cases, and beside them a `\r\n`
    leading newline, a whitespace line shorter than the indent, and a
    single-line literal, each with the value ponyc's `normalise_string`
    gives.
    """
    let q = "\"\"\""
    let cases: Array[(String val, String val)] val = [
      (q + "\nFoo" + q, "Foo")
      (q + "\nFoo\"bar" + q, "Foo\"bar")
      (q + "\nFoo\"\"bar" + q, "Foo\"\"bar")
      (q + "\nFoobar\"\"\"\"", "Foobar\"")
      (q + "\nFoobar\"\"\"\"\"\"", "Foobar\"\"\"")
      (q + "\nFoobar\"\"\"\"\"\"\"", "Foobar\"\"\"\"")
      (q + "\nFoo\nbar" + q, "Foo\nbar")
      (q + q, "")
      (q + "\n" + q, "")
      (q + " \t" + q, " \t")
      (q + "\tno newline here " + q, "\tno newline here ")
      (q + "\nFoo\\nbar" + q, "Foo\\nbar")
      (q + "\n   Foo\n   bar" + q, "Foo\nbar")
      (q + "\n   Foo\n     bar" + q, "Foo\n  bar")
      (q + "\n   Foo\n  bar" + q, " Foo\nbar")
      (q + "\n   Foo\n     bar\n    wom\n   bat" + q, "Foo\n  bar\n wom\nbat")
      (q + "\n   Foo\n     bar\n    \n   bat\n " + q, "Foo\n  bar\n \nbat\n")
      (q + "\n  Foo\n\n  bar" + q, "Foo\n\nbar")
      (q + "\nFoo\n\nbar" + q, "Foo\n\nbar")
      (q + "\nFoo\nbar\n  \t" + q, "Foo\nbar\n")
      (q + "\nFoo\nbar  " + q, "Foo\nbar  ")
      (q + "\r\n  Foo\r\n  bar" + q, "Foo\r\nbar")
      (q + "\n    Foo\n  \n    bar" + q, "Foo\nbar")
      (q + "one line" + q, "one line")
    ]
    for (text, value) in cases.values() do
      h.assert_eq[String](value, StringLiteralValue(text), text)
    end
