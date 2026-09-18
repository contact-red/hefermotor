use "collections"
use "itertools"
use "pony_test"
use "pony_check"

primitive \nodoc\ _LexerTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestCoversEverySource)
    test(_TestEmptySource)
    test(_TestWhitespaceRuns)
    test(_TestLineComment)
    test(_TestNestedComment)
    test(_TestUnterminatedNestedComment)
    test(_TestKeywordsAndIdentifiers)
    test(_TestGenericCapabilities)
    test(_TestSymbolLongestMatch)
    test(_TestNewlineForms)
    test(_TestNumbers)
    test(_TestStrings)
    test(_TestCharacterLiterals)
    test(_TestLexErrorDoesNotStopScanning)
    test(_TestNewlineInsideString)
    test(_TestEveryTruncationIsCovered)
    test(_TestScansOnDemand)
    test(_TestFailuresInTokenOrder)
    test(Property1UnitTest[(Array[U8] val, Array[USize] val)](
      _AccessOrderDoesNotMatter))

primitive \nodoc\ _Lex
  fun apply(src: String val): Array[(String val, String val)] =>
    """
    Lex `src` into `(kind name, exact text)` pairs, so a test can assert on
    both classification and extent at once.
    """
    let stream = _TokenStream(src)
    let out = Array[(String val, String val)]
    for (kind, offset, width) in stream.values() do
      out.push((kind.name(),
        recover val
          src.substring(offset.isize(), (offset + width).isize())
        end))
    end
    out

  fun kinds(src: String val): String val =>
    """
    The kind names in order, space separated, so that a failure prints the
    whole stream rather than the first index that differs.
    """
    " ".join(Iter[(String val, String val)](_Lex(src).values())
      .map[String val]({(p) => p._1 }))

primitive \nodoc\ _Assert
  fun covers(h: TestHelper, src: String val) =>
    """
    Every byte lies in exactly one token: widths sum to the source size, and
    only the final `TkEof` has zero width.
    """
    let stream = _TokenStream(src)
    var total: USize = 0
    var count: USize = 0
    var last = "".clone()
    for (kind, offset, width) in stream.values() do
      h.assert_eq[USize](total, offset, "token " + count.string() +
        " starts at " + offset.string() + ", expected " + total.string())
      total = total + width
      count = count + 1
      last = kind.name().clone()
      if kind.name() != "TkEof" then
        h.assert_ne[USize](0, width, "zero-width " + kind.name())
      end
    end
    h.assert_eq[USize](src.size(), total, "widths do not cover the source")
    h.assert_eq[String]("TkEof", consume last, "stream does not end at TkEof")

class \nodoc\ iso _TestCoversEverySource is UnitTest
  fun name(): String => "parse/lexer: covers every source"

  fun apply(h: TestHelper) =>
    """
    Losslessness, over sources chosen to reach every branch of the scanner.
    """
    let sources: Array[String val] = [
      ""
      " "
      "\n\n\n"
      "class Foo"
      "  fun bar(): U32 => 1 + 2\n"
      "// a comment"
      "// a comment\n"
      "/* a /* nested */ comment */"
      "/* unterminated"
      "\"a string\""
      "\"\"\"a docstring\"\"\""
      "\"unterminated"
      "'x'"
      "1 1.5 0x1f 0b1010 1e10 1.string()"
      "let x' = 1"
      "#read #send iso val"
      "a <<~ b << c < d"
      "\t\r\n  mixed \t whitespace \n"
      "`"
      "class Foo\n  let x: U32 = 1\n  fun f() =>\n    x\n"
    ]
    for src in sources.values() do
      _Assert.covers(h, src)
    end

class \nodoc\ iso _TestEmptySource is UnitTest
  fun name(): String => "parse/lexer: empty source"

  fun apply(h: TestHelper) =>
    let stream = _TokenStream("")
    (let kind, let width) = stream.token(0)
    h.assert_eq[String]("TkEof", kind.name())
    h.assert_eq[U32](0, width)
    h.assert_eq[USize](0, stream._scanned())

class \nodoc\ iso _TestWhitespaceRuns is UnitTest
  fun name(): String => "parse/lexer: whitespace is one token per run"

  fun apply(h: TestHelper) =>
    let got = _Lex("a \t\n  b")
    h.assert_eq[String]("TkId TkWhitespace TkId TkEof",
      _Lex.kinds("a \t\n  b"))
    try
      h.assert_eq[String](" \t\n  ", got(1)?._2)
    else
      h.fail("no whitespace token")
    end

class \nodoc\ iso _TestLineComment is UnitTest
  fun name(): String => "parse/lexer: line comment stops before the newline"

  fun apply(h: TestHelper) =>
    """
    The newline is whitespace and belongs to the next token, not to the
    comment. ponyc does the same, and a comment that swallowed its newline
    would lose the statement separator.
    """
    let got = _Lex("// hi\nx")
    h.assert_eq[String]("TkLineComment TkWhitespace TkId TkEof",
      _Lex.kinds("// hi\nx"))
    try
      h.assert_eq[String]("// hi", got(0)?._2)
      h.assert_eq[String]("\n", got(1)?._2)
    else
      h.fail("wrong shape")
    end

class \nodoc\ iso _TestNestedComment is UnitTest
  fun name(): String => "parse/lexer: nested comments nest"

  fun apply(h: TestHelper) =>
    let src = "/* a /* b */ c */x"
    let got = _Lex(src)
    try
      h.assert_eq[String]("TkNestedComment", got(0)?._1)
      h.assert_eq[String]("/* a /* b */ c */", got(0)?._2)
      h.assert_eq[String]("TkId", got(1)?._1)
    else
      h.fail("wrong shape")
    end

class \nodoc\ iso _TestUnterminatedNestedComment is UnitTest
  fun name(): String => "parse/lexer: unterminated nested comment is an error"

  fun apply(h: TestHelper) =>
    // ponyc's verdict: a comment that never closes is an error, like an
    // unterminated string. It still covers the rest of the source.
    let src = "x /* never closed"
    _Assert.covers(h, src)
    h.assert_eq[String]("TkId TkWhitespace TkLexError TkEof",
      _Lex.kinds(src))

class \nodoc\ iso _TestKeywordsAndIdentifiers is UnitTest
  fun name(): String => "parse/lexer: keywords and identifiers"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("TkClass TkWhitespace TkId TkEof",
      _Lex.kinds("class Foo"))
    // A word that merely starts with a keyword is an identifier.
    h.assert_eq[String]("TkId TkEof",
      _Lex.kinds("classy"))
    // Pony allows a trailing prime.
    h.assert_eq[String]("TkId TkEof",
      _Lex.kinds("x'"))
    h.assert_eq[String]("TkId TkEof",
      _Lex.kinds("x''"))
    h.assert_eq[String]("TkId TkEof",
      _Lex.kinds("_private"))

class \nodoc\ iso _TestGenericCapabilities is UnitTest
  fun name(): String => "parse/lexer: generic capabilities"

  fun apply(h: TestHelper) =>
    """
    `#read` and friends are keywords whose text includes the hash. A hash
    that spells none of them is a bare `TkConstant`.
    """
    h.assert_eq[String]("TkCapRead TkEof",
      _Lex.kinds("#read"))
    h.assert_eq[String]("TkCapSend TkEof",
      _Lex.kinds("#send"))
    h.assert_eq[String]("TkConstant TkId TkEof",
      _Lex.kinds("#nonsense"))

class \nodoc\ iso _TestSymbolLongestMatch is UnitTest
  fun name(): String => "parse/lexer: symbols take the longest match"

  fun apply(h: TestHelper) =>
    """
    `<<~` must not be lexed as `<<` then `~`, nor as `<` three times.
    """
    h.assert_eq[String]("TkLshiftTilde TkEof",
      _Lex.kinds("<<~"))
    h.assert_eq[String]("TkLshift TkEof",
      _Lex.kinds("<<"))
    h.assert_eq[String]("TkLt TkEof",
      _Lex.kinds("<"))
    h.assert_eq[String]("TkEllipsis TkEof",
      _Lex.kinds("..."))
    h.assert_eq[String]("TkDot TkDot TkEof",
      _Lex.kinds(".."))

class \nodoc\ iso _TestNewlineForms is UnitTest
  fun name(): String => "parse/lexer: newline forms of ( [ -"

  fun apply(h: TestHelper) =>
    """
    Pony tells a call's `(` from a grouped expression's by whether a newline
    precedes it. A nested comment clears the flag; a line comment does not,
    because the newline that ends the line comment sets it again.
    """
    h.assert_eq[String]("TkId TkLparen TkRparen TkEof",
      _Lex.kinds("f()"))
    h.assert_eq[String]("TkId TkWhitespace TkLparenNew TkRparen TkEof",
      _Lex.kinds("f\n()"))
    // Start of file counts as a newline.
    h.assert_eq[String]("TkLparenNew TkRparen TkEof",
      _Lex.kinds("()"))
    // A nested comment suppresses the newline form.
    h.assert_eq[String](
      "TkId TkWhitespace TkNestedComment TkLparen TkRparen TkEof",
      _Lex.kinds("f\n/* c */()"))

class \nodoc\ iso _TestNumbers is UnitTest
  fun name(): String => "parse/lexer: numbers"

  fun apply(h: TestHelper) =>
    """
    A `.` starts a fraction only when a digit follows, or `1.string()` would
    lex as a malformed float rather than an integer, a dot and a name.
    """
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("1"))
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("1_000"))
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("0x1fA"))
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("0b1010"))
    h.assert_eq[String]("TkFloat TkEof",
      _Lex.kinds("1.5"))
    h.assert_eq[String]("TkFloat TkEof",
      _Lex.kinds("1e10"))
    h.assert_eq[String]("TkFloat TkEof",
      _Lex.kinds("1.5e-3"))
    h.assert_eq[String]("TkInt TkDot TkId TkLparen TkRparen TkEof",
      _Lex.kinds("1.string()"))

class \nodoc\ iso _TestStrings is UnitTest
  fun name(): String => "parse/lexer: strings"

  fun apply(h: TestHelper) =>
    let got = _Lex("\"a\\\"b\"")
    h.assert_eq[String]("TkString TkEof",
      _Lex.kinds("\"hi\""))
    h.assert_eq[String]("TkString TkEof",
      _Lex.kinds("\"\"\"doc\"\"\""))
    // An escaped quote does not end the string.
    try
      h.assert_eq[String]("TkString", got(0)?._1)
      h.assert_eq[String]("\"a\\\"b\"", got(0)?._2)
    else
      h.fail("escape not handled")
    end
    // Unterminated is an error covering what remains, as ponyc has it.
    h.assert_eq[String]("TkLexError TkEof",
      _Lex.kinds("\"open"))

class \nodoc\ iso _TestCharacterLiterals is UnitTest
  fun name(): String => "parse/lexer: character literals"

  fun apply(h: TestHelper) =>
    """
    ponyc lexes a character literal as an integer.
    """
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("'x'"))
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("'\\n'"))
    h.assert_eq[String]("TkInt TkEof",
      _Lex.kinds("'\\''"))

class \nodoc\ iso _TestLexErrorDoesNotStopScanning is UnitTest
  fun name(): String => "parse/lexer: a lex error does not stop scanning"

  fun apply(h: TestHelper) =>
    """
    The point of error tolerance: a byte that starts no token costs that
    byte and nothing more.
    """
    let src = "a ` b"
    _Assert.covers(h, src)
    h.assert_eq[String]("TkId TkWhitespace TkLexError TkWhitespace TkId TkEof",
      _Lex.kinds(src))

class \nodoc\ iso _TestNewlineInsideString is UnitTest
  fun name(): String => "parse/lexer: a raw newline may appear in a string"

  fun apply(h: TestHelper) =>
    """
    ponyc's `string` scans to the closing quote or to the end of the source
    and checks for nothing else, so a literal may span lines.
    `files/_non_root_test.pony` in the standard library does this, and it is
    the one case that a whole-corpus comparison against ponyc caught and
    hand-written cases did not.
    """
    let src = "\"a\nb\""
    _Assert.covers(h, src)
    h.assert_eq[String]("TkString TkEof", _Lex.kinds(src))

class \nodoc\ iso _TestEveryTruncationIsCovered is UnitTest
  fun name(): String => "parse/lexer: every truncation is covered"

  fun apply(h: TestHelper) =>
    """
    Error tolerance, exhaustively over one input: cutting a source at any
    byte must still produce a stream that covers it. Truncation is what
    reaches the unterminated string, comment and literal paths, and it is
    what a buffer looks like halfway through being typed.
    """
    let src =
      "class Foo\n" +
      "  \"\"\"A docstring with a /* comment */ inside.\"\"\"\n" +
      "  let x: U32 = 0x1f\n" +
      "  fun f(): F64 =>\n" +
      "    // a line comment\n" +
      "    /* a /* nested */ comment */\n" +
      "    let s = \"a string with \\\" an escape\"\n" +
      "    let c = 'x'\n" +
      "    1.5e-3 + 1.string().size()\n"
    var cut: USize = 0
    while cut <= src.size() do
      _Assert.covers(h, recover val src.substring(0, cut.isize()) end)
      cut = cut + 1
    end

primitive \nodoc\ _TokenKindTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestKeywordsRoundTrip)
    test(_TestKeywordsRejectsNonKeywords)
    test(_TestSymbolsRoundTrip)
    test(_TestSymbolsPrecedeTheirPrefixes)
    test(_TestSymbolsAreDistinct)
    test(_TestNewlineForm)
    test(_TestKindNamesAreDistinct)
    test(_TestFixedTextIsNonEmpty)

class \nodoc\ iso _TestKeywordsRoundTrip is UnitTest
  fun name(): String => "parse/token kinds: keywords round-trip"

  fun apply(h: TestHelper) =>
    """
    Every kind whose text is fixed and which `_Keywords` recognises must map
    back to itself. This is what stops the two generated tables drifting.
    """
    var checked: USize = 0
    for kind in _AllTokenKinds().values() do
      match kind.text()
      | let t: String val =>
        match _Keywords(t)
        | let found: TokenKind =>
          h.assert_eq[String](kind.name(), found.name(),
            "_Keywords(\"" + t + "\") gave " + found.name())
          checked = checked + 1
        end
      end
    end
    // ponyc's keyword table has 77 entries; fewer would mean the generator
    // silently dropped some.
    h.assert_eq[USize](77, checked, "wrong number of keywords recognised")

class \nodoc\ iso _TestKeywordsRejectsNonKeywords is UnitTest
  fun name(): String => "parse/token kinds: keywords rejects non-keywords"

  fun apply(h: TestHelper) =>
    for s in ["".clone(); "nonsense"; "Use"; "use2"; "clas"; "("].values() do
      h.assert_is[(TokenKind | None)](None, _Keywords(consume s))
    end

class \nodoc\ iso _TestSymbolsRoundTrip is UnitTest
  fun name(): String => "parse/token kinds: symbols round-trip"

  fun apply(h: TestHelper) =>
    """
    Every `_Symbols` row carries its kind's own text, and every kind with
    a fixed text that is not a keyword has a row, except the five kinds
    ponyc's table lists under a text an earlier row already took. This
    is what stops a symbol dropping out of the scan table while its
    kind stays.
    """
    let rows = Map[String, String]
    for (text, kind) in _Symbols().values() do
      match kind.text()
      | let t: String val => h.assert_eq[String](t, text, kind.name())
      | None => h.fail(kind.name() + " has no fixed text")
      end
      rows(kind.name()) = text
    end
    let absent = ["TkUnaryMinus"; "TkLparenNew"; "TkLsquareNew"
      "TkMinusTildeNew"; "TkMinusNew"]
    var checked: USize = 0
    for kind in _AllTokenKinds().values() do
      match kind.text()
      | let t: String val =>
        if _Keywords(t) isnt None then continue end
        if absent.contains(kind.name(), {(a, b) => a == b}) then
          h.assert_false(rows.contains(kind.name()),
            kind.name() + " is in _Symbols")
          continue
        end
        h.assert_true(rows.contains(kind.name()),
          kind.name() + " is not in _Symbols")
        checked = checked + 1
      end
    end
    // ponyc's symbol table has 59 entries, five of them under a repeated
    // text; fewer would mean the generator silently dropped some.
    h.assert_eq[USize](54, checked, "wrong number of symbols")
    h.assert_eq[USize](54, _Symbols().size(), "wrong number of rows")

class \nodoc\ iso _TestSymbolsPrecedeTheirPrefixes is UnitTest
  fun name(): String => "parse/token kinds: symbols precede their prefixes"

  fun apply(h: TestHelper) =>
    """
    A scanner takes the first entry that matches, so a symbol must come
    before every symbol that is a prefix of it -- otherwise `<` would
    shadow `<<~`. This is the property of ponyc's table order that makes
    first match the longest match.
    """
    let rows = _Symbols()
    for (i, (text, _)) in rows.pairs() do
      for (j, (later, _)) in rows.pairs() do
        if (j > i) and later.at(text, 0) then
          h.fail("\"" + later + "\" follows its prefix \"" + text + "\"")
        end
      end
    end

class \nodoc\ iso _TestSymbolsAreDistinct is UnitTest
  fun name(): String => "parse/token kinds: symbols are distinct"

  fun apply(h: TestHelper) =>
    """
    ponyc's table lists `(`, `[`, `-` and `-~` more than once and its scan
    reaches only the first. A duplicate here would be an entry that can
    never match.
    """
    let seen = Set[String]
    for (text, _) in _Symbols().values() do
      h.assert_false(seen.contains(text), "duplicate symbol: " + text)
      seen.set(text)
    end

class \nodoc\ iso _TestNewlineForm is UnitTest
  fun name(): String => "parse/token kinds: newline form"

  fun apply(h: TestHelper) =>
    // The four ponyc maps, and only when a newline precedes.
    h.assert_is[TokenKind](TkLparenNew, _NewlineForm(TkLparen, true))
    h.assert_is[TokenKind](TkLsquareNew, _NewlineForm(TkLsquare, true))
    h.assert_is[TokenKind](TkMinusNew, _NewlineForm(TkMinus, true))
    h.assert_is[TokenKind](TkMinusTildeNew, _NewlineForm(TkMinusTilde, true))

    h.assert_is[TokenKind](TkLparen, _NewlineForm(TkLparen, false))
    h.assert_is[TokenKind](TkMinus, _NewlineForm(TkMinus, false))

    // Everything else is unchanged either way.
    h.assert_is[TokenKind](TkPlus, _NewlineForm(TkPlus, true))
    h.assert_is[TokenKind](TkId, _NewlineForm(TkId, true))

class \nodoc\ iso _TestKindNamesAreDistinct is UnitTest
  fun name(): String => "parse/token kinds: names are distinct"

  fun apply(h: TestHelper) =>
    """
    `name()` identifies a kind in diagnostics and in test failures, so two
    kinds sharing one would make a failure point at the wrong place.
    """
    let seen = Set[String]
    for kind in _AllTokenKinds().values() do
      h.assert_false(seen.contains(kind.name()), "duplicate: " + kind.name())
      seen.set(kind.name())
    end
    h.assert_eq[USize](145, seen.size(), "wrong number of token kinds")

class \nodoc\ iso _TestFixedTextIsNonEmpty is UnitTest
  fun name(): String => "parse/token kinds: fixed text is non-empty"

  fun apply(h: TestHelper) =>
    """
    A kind either fixes its text or it does not. An empty string would be a
    third state that the width of a token could not distinguish from the
    first.
    """
    for kind in _AllTokenKinds().values() do
      match kind.text()
      | let t: String val =>
        h.assert_ne[USize](0, t.size(), kind.name() + " has empty text")
      end
    end

class \nodoc\ iso _TestScansOnDemand is UnitTest
  fun name(): String => "parse/lexer: scans on demand"

  fun apply(h: TestHelper) =>
    """
    `token(i)` scans up to token `i` and no further, and past the end
    every index is `(TkEof, 0)` without scanning anything more.
    """
    let src = recover val
      let s = String
      var i: USize = 0
      while i < 10_000 do s.append("x "); i = i + 1 end
      consume s
    end
    let stream = _TokenStream(src)
    h.assert_eq[String]("TkId", stream.token(0)._1.name())
    h.assert_eq[USize](1, stream._scanned())
    h.assert_eq[String]("TkWhitespace", stream.token(7)._1.name())
    h.assert_eq[USize](8, stream._scanned())
    h.assert_eq[String]("TkId", stream.token(2)._1.name())
    h.assert_eq[USize](8, stream._scanned())
    (let kind, let width) = stream.token(20_000)
    h.assert_eq[String]("TkEof", kind.name())
    h.assert_eq[U32](0, width)
    h.assert_eq[USize](20_000, stream._scanned())
    h.assert_eq[String]("TkEof", stream.token(30_000)._1.name())
    h.assert_eq[USize](20_000, stream._scanned())

class \nodoc\ iso _TestFailuresInTokenOrder is UnitTest
  fun name(): String => "parse/lexer: failures in token order"

  fun apply(h: TestHelper) =>
    """
    Each refused token is in the failure list with its index, offset
    and length, in token order, and the cursor walks them once. A byte
    that starts no token is one failure of one byte, and an unterminated
    literal or comment is one to the end of the source.
    """
    // `abc $ b <0xEF> /* x`: the failures are tokens 2, 6 and 8 at
    // offsets 4, 8 and 10, so an index cannot pass for an offset.
    let stream = _TokenStream(String.from_array(
      [as U8: 'a'; 'b'; 'c'; ' '; '$'; ' '; 'b'; ' '; 0xEF; ' '; '/'; '*'
        ' '; 'x']))
    h.assert_is[(Any | None)](None, stream.next_failure(),
      "a failure before anything is scanned")
    stream.take_failure()
    h.assert_eq[String]("TkLexError", stream.token(2)._1.name())
    match stream.next_failure()
    | (let index: USize, let f: UnrecognizedCharacter, let at: USize,
      let len: USize)
    =>
      h.assert_eq[USize](2, index)
      h.assert_eq[U8]('$', f.byte)
      h.assert_eq[USize](4, at)
      h.assert_eq[USize](1, len)
    else
      h.fail("expected UnrecognizedCharacter('$')")
    end
    stream.take_failure()
    h.assert_is[(Any | None)](None, stream.next_failure(),
      "a failure past the scanned tokens")
    stream.take_failure()
    h.assert_eq[String]("TkEof", stream.token(100)._1.name())
    match stream.next_failure()
    | (let index: USize, let f: UnrecognizedCharacter, let at: USize,
      let len: USize)
    =>
      h.assert_eq[USize](6, index)
      h.assert_eq[U8](0xEF, f.byte)
      h.assert_eq[USize](8, at)
      h.assert_eq[USize](1, len)
    else
      h.fail("expected UnrecognizedCharacter(0xEF)")
    end
    stream.take_failure()
    match stream.next_failure()
    | (let index: USize, UnterminatedComment, let at: USize,
      let len: USize)
    =>
      h.assert_eq[USize](8, index)
      h.assert_eq[USize](10, at)
      h.assert_eq[USize](4, len)
    else
      h.fail("expected UnterminatedComment")
    end
    stream.take_failure()
    h.assert_is[(Any | None)](None, stream.next_failure())
    for (src, index, at, len) in
      [as (String, USize, USize, USize):
        ("'a", 0, 0, 2); ("x \"ab", 2, 2, 3); ("x \"\"\"ab\"", 2, 2, 6)]
        .values()
    do
      let literal = _TokenStream(src)
      literal.token(index)
      match literal.next_failure()
      | (index, UnterminatedLiteral, at, len) => None
      else
        h.fail("expected UnterminatedLiteral over the rest of " + src)
      end
    end

primitive \nodoc\ _Frozen[A: Any val]
  fun apply(a: Array[A] box): Array[A] val =>
    let out = recover iso Array[A](a.size()) end
    for x in a.values() do out.push(x) end
    consume out

primitive \nodoc\ _Sized[A: Any val]
  fun apply(gen: Generator[A], sizes: Generator[USize])
    : Generator[Array[A] val]
  =>
    """
    Arrays whose size is drawn from `sizes`. pony_check's `array_of`
    with a lower bound of zero stops after each element on a coin toss,
    so its sizes are almost always below three.
    """
    sizes.flat_map[Array[A] val]({(n: USize) =>
      Generators.array_of[A](gen, n, n)
        .map[Array[A] val]({(a: Array[A]) => _Frozen[A](a) }) })

primitive \nodoc\ _EagerScan
  """
  Every token of a source in one pass, over the lexer's own scanning
  helpers, with the newline flag carried in a local. `token(i)` must
  give the same tokens whatever order it is asked in, so this is the
  oracle for the state a stream carries between calls.
  """
  fun apply(src: String val): Array[(TokenKind, U32)] =>
    let stream = _TokenStream(src)
    let out = Array[(TokenKind, U32)]
    let n = src.size()
    var i: USize = 0
    var after_newline = true
    while i < n do
      let c = try src(i)? else 0 end
      if (c == ' ') or (c == '\t') or (c == '\r') or (c == '\n') then
        (let j, let saw_newline) = stream._space(i, n)
        out.push((TkWhitespace, (j - i).u32()))
        if saw_newline then after_newline = true end
        i = j
      elseif (c == '/') and (stream._byte(i + 1) == '/') then
        let j = stream._line_comment(i, n)
        out.push((TkLineComment, (j - i).u32()))
        i = j
      elseif (c == '/') and (stream._byte(i + 1) == '*') then
        (let j, let terminated) = stream._nested_comment(i, n)
        out.push((if terminated then TkNestedComment else TkLexError end,
          (j - i).u32()))
        after_newline = false
        i = j
      else
        (let kind, let j, _) = stream._token(i, n, after_newline)
        out.push((kind, (j - i).u32()))
        after_newline = false
        i = j
      end
    end
    out

class \nodoc\ iso _AccessOrderDoesNotMatter
  is Property1[(Array[U8] val, Array[USize] val)]
  """
  Over arbitrary bytes and an arbitrary access sequence -- repeats,
  jumps forward, an index past the end and then an earlier one -- every
  `token(i)` equals the eager scan's `i`-th token, the eager scan's
  widths sum to the source size, the token after the last is `TkEof`
  with width 0 and so is an index five past it, `_scanned()` never
  exceeds the largest index asked for plus one, and the failure list
  holds one record per `TkLexError` scanned, with that token's index,
  offset and width.
  """
  fun name(): String => "parse/lexer: access order does not matter"

  fun params(): PropertyParams =>
    PropertyParams(where num_samples' = 400)

  fun gen(): Generator[(Array[U8] val, Array[USize] val)] =>
    // Sources are fragments joined: single bytes, and the openers and
    // closers that take more than one byte to reach, so that comments,
    // triple-quoted strings and a newline before a symbol with a
    // newline form are common shapes.
    let interesting: Array[U8] val =
      [' '; '\n'; '\t'; '"'; '\''; '/'; '*'; '('; '['; '-'; '~'; '<'
        '='; '.'; '_'; '0'; '9'; 'x'; 'e'; '#'; '$'; '\\'; 0xEF; 0]
    let multi: Array[String] val =
      ["//"; "/*"; "*/"; "\"\"\""; "\n("; "\n["; "\n-"; "\n-~"; "/* */("]
    let one = {(b: U8): String => String.from_array([b]) }
    let fragment: Generator[String] = Generators.frequency[String]([
      (6, Generators.one_of[U8](interesting).map[String](one))
      (2, Generators.u8(0, 127).map[String](one))
      (1, Generators.u8().map[String](one))
      (3, Generators.one_of[String](multi))
    ])
    _Sized[String](fragment, Generators.usize(0, 24))
      .map[Array[U8] val]({(parts: Array[String] val) =>
        let out = recover iso Array[U8] end
        for part in parts.values() do out.append(part.array()) end
        consume out })
      .flat_map[(Array[U8] val, Array[USize] val)](
        {(bytes: Array[U8] val) =>
          // A token is at least one byte, so indices up to the size
          // reach every token and a few past it reach the end.
          _Sized[USize](Generators.usize(0, bytes.size() + 3),
            Generators.usize(0, 12))
            .map[(Array[U8] val, Array[USize] val)](
              {(accesses: Array[USize] val) => (bytes, accesses) }) })

  fun property(sample: (Array[U8] val, Array[USize] val), h: PropertyHelper)
  =>
    (let bytes, let accesses) = sample
    let src = String.from_array(bytes)
    let expected = _EagerScan(src)
    var total: USize = 0
    for (_, width) in expected.values() do total = total + width.usize() end
    h.assert_eq[USize](src.size(), total, "widths do not cover the source")
    let random = _TokenStream(src)
    var highest: USize = 0
    for i in accesses.values() do
      (let kind, let width) = random.token(i)
      highest = highest.max(i)
      try
        (let k, let w) = expected(i)?
        h.assert_true(kind is k, "token " + i.string() + " is " +
          kind.name() + ", in order it is " + k.name())
        h.assert_eq[U32](w, width, "width of token " + i.string())
      else
        h.assert_true(kind is TkEof, "token " + i.string() + " past the end")
        h.assert_eq[U32](0, width, "width past the end")
      end
      h.assert_true(random._scanned() <= (highest + 1),
        "scanned " + random._scanned().string() + " tokens for index " +
        highest.string())
    end
    (let after, let after_width) = random.token(expected.size())
    h.assert_true(after is TkEof, "the token after the last is not TkEof")
    h.assert_eq[U32](0, after_width, "the token after the last has a width")
    h.assert_true(random.token(expected.size() + 5)._1 is TkEof,
      "a later index is not TkEof")
    // Every token is now scanned: the failure list is one record per
    // TkLexError, in token order, with the token's index, offset and
    // width.
    var offset: USize = 0
    for (i, (kind, width)) in expected.pairs() do
      if kind is TkLexError then
        match random.next_failure()
        | (let index: USize, _, let at: USize, let len: USize) =>
          h.assert_eq[USize](i, index, "failure index")
          h.assert_eq[USize](offset, at, "failure offset")
          h.assert_eq[USize](width.usize(), len, "failure length")
        else
          h.fail("no failure recorded for token " + i.string())
        end
        random.take_failure()
      end
      offset = offset + width.usize()
    end
    h.assert_true(random.next_failure() is None,
      "a failure with no TkLexError")
