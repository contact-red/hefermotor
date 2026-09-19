use "pony_test"
use diag = "../diagnostics"
use source = "../source"

primitive \nodoc\ _DiagnosticTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestExpectedFamily)
    test(_TestExpectedNouns)
    test(_TestExpectedAtEof)
    test(_TestEntryGates)
    test(_TestCasePattern)
    test(_TestSequenceStopsAfterJump)
    test(_TestUnterminatedFamily)
    test(_TestUnterminatedBeside)
    test(_TestUnterminatedBudget)
    test(_TestLexErrorRecordsNothing)
    test(_TestNestingRecord)
    test(_TestNestingAtEof)
    test(_TestBudgetThenJunk)
    test(_TestBudget)
    test(_TestBudgetThenNesting)
    test(_TestRecords)
    test(_TestJunkIsNotMerged)
    test(_TestEveryKindIsDescribed)

primitive \nodoc\ _Only
  """
  The one diagnostic of a source, with a failure when there is not
  exactly one.
  """
  fun apply(h: TestHelper, src: String val, label: String)
    : (diag.Diagnostic | None)
  =>
    let diagnostics = _Diagnostics(src)
    if diagnostics.size() != 1 then
      let out = recover iso String end
      for d in diagnostics.values() do
        out.append("\n  " + d.string())
      end
      h.fail(label + ": " + diagnostics.size().string() + " diagnostics" +
        consume out)
      return None
    end
    try diagnostics(0)? end

primitive \nodoc\ _Expected
  """
  Asserts one `parse/expected` diagnostic at a byte offset, with the
  message ponyc's rule description gives.
  """
  fun apply(h: TestHelper, src: String val, at: USize, message: String,
    label: String)
  =>
    match _Only(h, src, label)
    | let d: diag.Diagnostic =>
      h.assert_eq[String]("parse/expected", d.cause.code(), label)
      h.assert_eq[String](message, d.cause.message(), label)
      match d.location
      | let s: diag.Span =>
        h.assert_eq[USize](at, s.start, label + ": start")
        h.assert_eq[USize](0, s.length, label + ": length")
        h.assert_eq[String]("/test", s.dir, label)
        h.assert_eq[String]("test.pony", s.name, label)
      else
        h.fail(label + ": not a span")
      end
    end

class \nodoc\ iso _TestExpectedFamily is UnitTest
  fun name(): String => "parse/diagnostics: expected, one per ponyc probe"

  fun apply(h: TestHelper) =>
    """
    Each case records exactly one `parse/expected`, at the token ponyc
    stops at, naming ponyc's rule description. The probes, at
    `--pass=parse`:

    - `fun f(,)`: `2:9: expected ) after (`
    - `let x` then `fun`: `3:3: expected mandatory type declaration on
      field after x`
    - `if true then : 2 end`: `3:18: expected then value after then`
    - `foo(1, )`: `3:12: expected argument after ,`
    - `while true do end`: `3:19: expected while body after do`
    - `fun f() => "a";` then `fun g`: `3:3: expected value after
      semicolon`

    hefermotor names the token found where ponyc names the token
    before; the positions agree.
    """
    _Expected(h, "class C\n  fun f(,)\n", 16,
      "syntax error: expected ), found ,", "params")
    _Expected(h, "class C\n  let x\n  fun g() => 1\n", 18,
      "syntax error: expected mandatory type declaration on field, " +
      "found fun", "field type")
    _Expected(h, "actor Main\n  new create(env: Env) =>\n" +
      "    if true then : 2 end\n", 54,
      "syntax error: expected then value, found :", "then value")
    _Expected(h, "actor Main\n  new create(env: Env) =>\n    foo(1, )\n",
      48, "syntax error: expected argument, found )", "argument")
    _Expected(h, "actor Main\n  new create(env: Env) =>\n" +
      "    while true do end\n", 55,
      "syntax error: expected while body, found end", "while body")
    _Expected(h, "class C\n  fun f() => \"a\";\n  fun g() => 1\n", 28,
      "syntax error: expected value, found fun", "after a semicolon")

class \nodoc\ iso _TestExpectedNouns is UnitTest
  fun name(): String => "parse/diagnostics: the nouns of the threaded sites"

  fun apply(h: TestHelper) =>
    """
    One case per site that takes its noun from its caller: the type
    sites, and the rules whose first token is a name. Each records one
    `parse/expected` where `ponyc --pass=parse` stops, with its rule
    description.
    """
    let cases: Array[(String val, USize, String val)] = [
      ("class C is\n  fun f() => 1\n", 13, "provided type, found fun")
      ("class C\n  let x:\n  fun g() => 1\n", 19, "field type, found fun")
      ("class C\n  fun f():\n  fun g() => 1\n", 21, "return type, found fun")
      ("class C\n  fun f(x:)\n", 18, "parameter type, found )")
      ("class C[]\n", 8, "type parameter, found ]")
      ("class C\n  fun f(x: A,)\n", 21, "parameter, found )")
      ("class C\n  fun f() =>\n    g(where )\n", 33,
        "named argument, found )")
      ("class C\n  fun f() =>\n    for in a do b end\n", 29,
        "iterator name, found in")
      ("class C\n  fun f() =>\n    with = a do b end\n", 30,
        "with expression, found =")
      ("class C\n  let x: {(,)}\n", 19, "), found ,")
      ("class C\n  let x: A[]\n", 19, "type argument, found ]")
      ("class C\n  fun f() =>\n    let x: = 1\n", 32, "variable type, found =")
    ]
    for (src, position, tail) in cases.values() do
      _Expected(h, src, position, "syntax error: expected " + tail, src)
    end

class \nodoc\ iso _TestExpectedAtEof is UnitTest
  fun name(): String => "parse/diagnostics: an expectation at the end"

  fun apply(h: TestHelper) =>
    """
    An expectation at the end of the file is positioned at the start of
    the last significant token and names the end: ponyc's `2:9:
    expected assign rhs after =` and `1:5: expected = after x`.
    """
    _Expected(h, "class C\n  fun f() =>\n    x =\n", 27,
      "syntax error: expected assign rhs, found the end of the file",
      "assign at the end")
    _Expected(h, "use x\n", 4,
      "syntax error: expected =, found the end of the file",
      "use at the end")

primitive \nodoc\ _Exactly
  """
  Asserts a source's diagnostics are exactly the given (code, start,
  message) rows, in order, and that `TreeCheck` finds nothing.
  """
  fun apply(h: TestHelper, src: String val,
    rows: Array[(String val, USize, String val)] val, label: String)
  =>
    let diagnostics = _Diagnostics(src)
    h.assert_eq[USize](rows.size(), diagnostics.size(), label + ": count")
    var i: USize = 0
    while (i < rows.size()) and (i < diagnostics.size()) do
      try
        (let code, let start, let message) = rows(i)?
        let d = diagnostics(i)?
        h.assert_eq[String](code, d.cause.code(), label + " " + i.string())
        h.assert_eq[USize](start, _Start(d), label + " " + i.string())
        h.assert_eq[String](message, d.cause.message(),
          label + " " + i.string())
      else
        _Unreachable()
      end
      i = i + 1
    end
    for v in _Check(src).values() do h.fail(label + ": " + v.string()) end

class \nodoc\ iso _TestEntryGates is UnitTest
  fun name(): String => "parse/diagnostics: optional rules are gated"

  fun apply(h: TestHelper) =>
    """
    An optional rule is entered only where its first token can start
    it, so a token that cannot start it, in its place, is not an
    expected argument or parameter: ponyc's `3:6: unterminated call
    arguments` and `3:7: expected ) after (`. The lambda's `}` is in
    the source but the rules inside stop at the `,`, so the lambda is
    recorded unterminated too.
    """
    _Exactly(h, "class C\n  fun f() =>\n    g(])\n", [
      ("parse/unterminated", 26, "syntax error: unterminated call arguments")
      ("parse/expected", 27, "syntax error: expected field or method, " +
        "found ]")
    ], "call arguments")
    _Exactly(h, "class C\n  fun f() =>\n    {(,) => 1 }\n", [
      ("parse/unterminated", 25,
        "syntax error: unterminated lambda expression")
      ("parse/expected", 27, "syntax error: expected ), found ,")
    ], "lambda parameters")

class \nodoc\ iso _TestUnterminatedFamily is UnitTest
  fun name(): String =>
    "parse/diagnostics: unterminated, one per TERMINATE rule"

  fun apply(h: TestHelper) =>
    """
    One row per ponyc `TERMINATE` rule: the construct left open
    records exactly one `parse/unterminated`, over its opening token,
    naming ponyc's construct, with `before` at the token found in place
    of the closer, which is the last significant token where the file
    ends. Each row's opener and that token are found in its source.
    ponyc at `--pass=parse` reports every row as `unterminated <what>`
    at the opener with `expected terminating <closer> before here` at
    that token. The array rows are a first statement and a
    continuation statement, ponyc's `array` and `nextarray`.
    """
    let body_rows: Array[(String val, String val, String val, String val)]
      val = [
      ("x.foo[U8", "type arguments", "[", "U8")
      ("if \\a, b true then 1 end", "annotations", "\\", "true")
      ("object fun f() => 1", "object literal", "object", "1")
      ("{(x: U8) => x", "lambda expression", "{", "x")
      ("@{(x: U8) => x", "lambda expression", "@{", "x")
      ("[1; 2", "array literal", "[", "2")
      ("1\n    [1; 2", "array literal", "[", "2")
      ("@foo[U8](1", "ffi arguments", "@", "1")
      ("foo(1", "call arguments", "(", "1")
      ("if true then 1", "if expression", "if", "1")
      ("ifdef linux then 1", "ifdef expression", "ifdef", "1")
      ("iftype A <: B then 1", "iftype expression", "iftype", "1")
      ("match x | 1 => 2", "match expression", "match", "2")
      ("while true do 1", "while loop", "while", "1")
      ("repeat 1 until false", "repeat loop", "repeat", "false")
      ("for x in y do 1", "for loop", "for", "1")
      ("with x = y do 1", "with expression", "with", "1")
      ("try 1 else 2", "try expression", "try", "2")
      ("recover iso String", "recover expression", "recover", "String")
    ]
    for (body, what, opener, last) in body_rows.values() do
      _one(h, _Nested.body(body), what, body, opener, last, 41)
    end
    _one(h, "class C[A: Any\n", "type parameters", "class C[A: Any\n", "[",
      "Any", 0)
    _one(h, "use @foo[U8(x: U8)\n", "type arguments", "use @foo[U8(x: U8)\n",
      "[", "(", 0)

  fun _one(h: TestHelper, src: String val, what: String val,
    body: String val, opener: String val, last: String val, base: USize)
  =>
    """
    Exactly one diagnostic in `src`, a `parse/unterminated` over
    `opener`'s first occurrence in `body` (which starts `base` bytes
    into `src`), with `before` at `last`'s last occurrence.
    """
    var found: USize = 0
    let diagnostics = _Diagnostics(src)
    h.assert_eq[USize](1, diagnostics.size(), body + ": diagnostics")
    for d in diagnostics.values() do
      match d.cause
      | let u: SyntaxUnterminated =>
        found = found + 1
        h.assert_eq[String](what, u.what, body)
        h.assert_eq[String]("syntax error: unterminated " + what,
          d.cause.message(), body)
        try
          h.assert_eq[USize](base + body.find(opener)?.usize(), _Start(d),
            body + ": opener")
          h.assert_eq[USize](base + body.rfind(last)?.usize(), u.before,
            body + ": before")
        else
          h.fail(body + ": opener or last token not in the source")
        end
        match d.location
        | let sp: diag.Span => h.assert_eq[USize](opener.size(), sp.length,
          body + ": width")
        else
          h.fail(body + ": not a span")
        end
      end
    end
    h.assert_eq[USize](1, found, body + ": unterminated records")
    for v in _Check(src).values() do h.fail(body + ": " + v.string()) end

class \nodoc\ iso _TestUnterminatedBeside is UnitTest
  fun name(): String =>
    "parse/diagnostics: a missing closer beside what was inside"

  fun apply(h: TestHelper) =>
    """
    A missing closer is recorded at the opener whatever was recorded
    inside the construct, so `foo(` alone has one record, `foo(1,` has
    the argument's and the opener's, sorted opener first where ponyc
    reports the argument only (`3:10: expected argument after ,`), and
    junk in an open `if` has the junk's and the opener's. Junk in a
    closed `if` has the junk's only, where ponyc reports the `if`
    unterminated. `fun f(` is not a `TERMINATE` site, so its `)` is an
    expectation, at the `(` since the file ends. A lexer refusal inside
    an open construct, or in place of its closer, excuses nothing at
    the opener, and is reported by the lexer beside it. An opener that
    is the last token shares its start with the expectation inside it,
    and sorts after it by width.
    """
    _Exactly(h, _Nested.body("foo("), [
      ("parse/unterminated", 44, "syntax error: unterminated call arguments")
    ], "foo(")
    _Exactly(h, _Nested.body("foo(1,"), [
      ("parse/unterminated", 44, "syntax error: unterminated call arguments")
      ("parse/expected", 46, "syntax error: expected argument, found the " +
        "end of the file")
    ], "foo(1,")
    _Exactly(h, "class C\n  fun f(\n", [
      ("parse/expected", 15, "syntax error: expected ), found the end of " +
        "the file")
    ], "fun f(")
    _Exactly(h, _Nested.body("if true then 1 : 2"), [
      ("parse/unterminated", 41, "syntax error: unterminated if expression")
      ("parse/expected", 56, "syntax error: expected value, found :")
    ], "open if")
    _Exactly(h, _Nested.body("if true then 1 : 2 end"), [
      ("parse/expected", 56, "syntax error: expected value, found :")
    ], "closed if")
    _Exactly(h, _Nested.body("foo(1 \""), [
      ("parse/unterminated", 44, "syntax error: unterminated call arguments")
      ("parse/lex", 47, "Literal doesn't terminate")
    ], "lexer refusal inside")
    _Exactly(h, _Nested.body("x.foo[U8 \""), [
      ("parse/unterminated", 46, "syntax error: unterminated type arguments")
      ("parse/lex", 50, "Literal doesn't terminate")
    ], "lexer refusal at the closer")
    _Exactly(h, "class C[A: Any \"\n", [
      ("parse/unterminated", 7, "syntax error: unterminated type parameters")
      ("parse/lex", 15, "Literal doesn't terminate")
    ], "lexer refusal at a type parameter list's closer")
    _Exactly(h, _Nested.body("x.foo["), [
      ("parse/expected", 46, "syntax error: expected type argument, found " +
        "the end of the file")
      ("parse/unterminated", 46, "syntax error: unterminated type arguments")
    ], "opener last")

class \nodoc\ iso _TestUnterminatedBudget is UnitTest
  fun name(): String => "parse/diagnostics: unterminated is budgeted"

  fun apply(h: TestHelper) =>
    """
    600 methods each leaving a call open record 500 `parse/unterminated`
    and one `parse/limit`, the 500 being the first 500, and `TreeCheck`
    is empty.
    """
    let src: String val = recover val
      "class C\n" + "  fun f() => g(\n".mul(600)
    end
    let diagnostics = _Diagnostics(src)
    h.assert_eq[USize](501, diagnostics.size())
    var unterminated: USize = 0
    var last: USize = 0
    for d in diagnostics.values() do
      match d.cause
      | let _: SyntaxUnterminated =>
        unterminated = unterminated + 1
        last = _Start(d)
      end
    end
    h.assert_eq[USize](500, unterminated)
    // The k-th `(` sits at 8 + (k - 1) * 16 + 14.
    h.assert_eq[USize](8 + (499 * 16) + 14, last)
    try
      h.assert_eq[String]("parse/limit", diagnostics(0)?.cause.code())
    else
      h.fail("no diagnostics")
    end
    for v in _Check(src).values() do h.fail(v.string()) end

class \nodoc\ iso _TestCasePattern is UnitTest
  fun name(): String => "parse/diagnostics: a case pattern is not an if"

  fun apply(h: TestHelper) =>
    """
    A case with a guard and no pattern is valid Pony, and a prefix
    operator in a case pattern is still followed by a case pattern:
    ponyc accepts `| if true => None` and reports `4:8: expected
    expression after -` for `| -if true => None`.
    """
    let clean: String val = "actor Main\n  new create(env: Env) =>\n" +
      "    match env\n    | if true => None\n    end\n"
    let tree = _ParseText(clean)
    _Clean(h, tree, clean)
    h.assert_eq[USize](1, _Find.count(tree, NdGuard))
    h.assert_eq[USize](0, _Find.count(tree, NdIf))
    _Expected(h, "actor Main\n  new create(env: Env) =>\n" +
      "    match env\n    | -if true => None\n    end\n", 58,
      "syntax error: expected expression, found if", "prefix then if")

class \nodoc\ iso _TestSequenceStopsAfterJump is UnitTest
  fun name(): String => "parse/diagnostics: a sequence stops after a jump"

  fun apply(h: TestHelper) =>
    """
    Nothing follows a jump in a sequence, so a `;` after `return` is
    reported from the member list, where ponyc's restart check reports
    `3:12: unexpected token ; after method body`.
    """
    _Expected(h, "class C\n  fun f() =>\n    return ;\n", 32,
      "syntax error: expected field or method, found ;", "after a jump")

class \nodoc\ iso _TestLexErrorRecordsNothing is UnitTest
  fun name(): String =>
    "parse/diagnostics: a lex error is the lexer's record alone"

  fun apply(h: TestHelper) =>
    """
    A rule failing on a token the lexer refused records nothing: the
    refusal is the lexer's record, the file's only one. The tree still
    wraps the token.
    """
    let src: String val = "class C\n  fun f() => $\n"
    _Exactly(h, src, [("parse/lex", 21, "Unrecognized character: $")],
      "refused token")
    h.assert_eq[USize](1, _Find.count(_ParseText(src), NdError))

class \nodoc\ iso _TestNestingRecord is UnitTest
  fun name(): String => "parse/diagnostics: the nesting record"

  fun apply(h: TestHelper) =>
    """
    A depth refusal is recorded over the token it refused, with the
    code, the limit and the site's noun.
    """
    let src: String val = _Nested.body(recover val
      "(".mul(1300) + "1" + ")".mul(1300) end)
    var found: USize = 0
    for d in _Diagnostics(src).values() do
      match d.cause
      | let n: NestingTooDeep =>
        found = found + 1
        h.assert_eq[String]("parse/nesting", d.cause.code())
        h.assert_eq[USize](2500, n.limit)
        h.assert_eq[String]("expression", n.what)
        h.assert_eq[String](
          "expression nested past the grammar depth limit of 2500",
          d.cause.message())
        match d.location
        | let s: diag.Span =>
          // The body starts 41 bytes in, and parentheses descend twice
          // a level, so the 1251st is the refused token.
          h.assert_eq[USize](41 + 1250, s.start)
          h.assert_eq[USize](1, s.length)
        else
          h.fail("not a span")
        end
      end
    end
    h.assert_eq[USize](1, found)

class \nodoc\ iso _TestNestingAtEof is UnitTest
  fun name(): String => "parse/diagnostics: a nesting record at the end"

  fun apply(h: TestHelper) =>
    """
    A depth refusal at the end of the file is positioned where an
    expectation there is: at the start of the last significant token,
    with width 0, so that it sorts with the expectation it caused
    rather than after the trailing newline.
    """
    let src: String val = _Nested.body(recover val "(".mul(1250) end)
    var found: USize = 0
    for d in _Diagnostics(src).values() do
      match d.cause
      | let _: NestingTooDeep =>
        found = found + 1
        h.assert_eq[USize](41 + 1249, _Start(d))
        match d.location
        | let s: diag.Span => h.assert_eq[USize](0, s.length)
        else
          h.fail("not a span")
        end
      end
    end
    h.assert_eq[USize](1, found)
    for v in _Check(src).values() do h.fail(v.string()) end

class \nodoc\ iso _TestBudget is UnitTest
  fun name(): String => "parse/diagnostics: the budget"

  fun apply(h: TestHelper) =>
    """
    600 `fun` tokens on their own lines each expect a method name at
    the next: 500 records are kept, one `SyntaxLimit` heads the list at
    the file, and the 501st is absent.
    """
    let src: String val = recover val "class C\n" + "  fun\n".mul(600) end
    let diagnostics = _Diagnostics(src)
    h.assert_eq[USize](501, diagnostics.size())
    try
      let first = diagnostics(0)?
      h.assert_eq[String]("parse/limit", first.cause.code())
      match first.location
      | let _: diag.FileOnly => None
      else
        h.fail("not at the file")
      end
      h.assert_eq[String](
        "more than 500 syntax errors in this file; the rest are not " +
        "reported", first.cause.message())
      var expected: USize = 0
      var last: USize = 0
      for d in diagnostics.values() do
        match d.cause
        | let _: SyntaxExpected => expected = expected + 1; last = _Start(d)
        end
      end
      h.assert_eq[USize](500, expected)
      // The k-th `fun` sits at 10 + (k - 1) * 6 and expects a name at
      // the next one, so the 500th kept record is at the 501st `fun`
      // and the 501st, at the 502nd, is absent.
      h.assert_eq[USize](10 + (500 * 6), last)
    else
      h.fail("no diagnostics")
    end

class \nodoc\ iso _TestBudgetThenNesting is UnitTest
  fun name(): String =>
    "parse/diagnostics: a nesting refusal past the budget is kept"

  fun apply(h: TestHelper) =>
    """
    A file that reaches the budget and then nests past the limit keeps
    its `NestingTooDeep` beside the `SyntaxLimit`, and `TreeCheck` is
    empty: the refused region's error node is accounted for by that
    record, which the budget never drops.
    """
    let src: String val = recover val
      "class C\n" + "  fun\n".mul(600) + "  fun g() => " + "(".mul(1300) +
        "\n"
    end
    var nesting: USize = 0
    var limit: USize = 0
    for d in _Diagnostics(src).values() do
      match d.cause
      | let _: NestingTooDeep => nesting = nesting + 1
      | let _: SyntaxLimit => limit = limit + 1
      end
    end
    h.assert_eq[USize](1, nesting)
    h.assert_eq[USize](1, limit)
    for v in _Check(src).values() do h.fail(v.string()) end

class \nodoc\ iso _TestBudgetThenJunk is UnitTest
  fun name(): String =>
    "parse/diagnostics: an error node past the budget is excused"

  fun apply(h: TestHelper) =>
    """
    A file that reaches the budget and then holds a token no rule
    accepts has an error node with no record at its offset, and
    `TreeCheck` is empty: the `SyntaxLimit` stands in for the dropped
    record.
    """
    let src: String val = recover val
      "class C\n" + "  fun\n".mul(600) + "  ? ?\n"
    end
    var limit: USize = 0
    for d in _Diagnostics(src).values() do
      match d.cause
      | let _: SyntaxLimit => limit = limit + 1
      end
    end
    h.assert_eq[USize](1, limit)
    h.assert_eq[USize](1, _Find.count(_ParseText(src), NdError))
    for v in _Check(src).values() do h.fail(v.string()) end

class \nodoc\ iso _TestRecords is UnitTest
  fun name(): String => "parse/diagnostics: the records"

  fun apply(h: TestHelper) =>
    """
    `note_expected` is false the second time for one token; the 501st
    budgeted record becomes the limit and the 502nd is dropped; an
    exempt record after them is kept; a `NestingTooDeep` and a
    `SyntaxExpected` at one offset are both kept, since only
    expectations are deduped.
    """
    let file = source.SourceFile("/t", "t.pony", "")
    let records = _Records(file)
    h.assert_true(records.note_expected(3))
    h.assert_false(records.note_expected(3))
    h.assert_true(records.note_expected(4))
    var i: USize = 0
    while i < 500 do
      records.record(SyntaxExpected("x", TkEof), i, 0)
      i = i + 1
    end
    records.record(SyntaxUnterminated("y", 0), 500, 1)
    records.record(SyntaxExpected("z", TkEof), 501, 0)
    records.record(NestingTooDeep("w", 2500), 502, 1)
    let taken: Array[diag.Diagnostic] val = records.take()
    h.assert_eq[USize](502, taken.size())
    try
      h.assert_eq[String]("parse/expected", taken(499)?.cause.code())
      h.assert_eq[String]("parse/limit", taken(500)?.cause.code())
      h.assert_eq[String]("parse/nesting", taken(501)?.cause.code())
      h.assert_eq[USize](502, _Start(taken(501)?))
    else
      h.fail("fewer records than expected")
    end
    h.assert_eq[USize](0, records.take().size(), "take leaves records")
    let fresh = _Records(file)
    fresh.record(SyntaxExpected("a", TkId), 5, 0)
    fresh.record(NestingTooDeep("b", 2500), 5, 1)
    fresh.record(SyntaxExpected("c", TkId), 5, 0)
    h.assert_eq[USize](3, fresh.take().size(),
      "the records drop nothing by offset")

class \nodoc\ iso _TestJunkIsNotMerged is UnitTest
  fun name(): String => "parse/diagnostics: junk tokens are not merged"

  fun apply(h: TestHelper) =>
    """
    Three junk tokens in a row in a body, each one that starts no
    expression, ends no sequence and is no operator, give three records
    and three one-token error nodes: each statement fails on its own
    token, and nothing merges adjacent error nodes.
    """
    let src: String val = "class C\n  fun f() =>\n    ? : ?\n"
    let diagnostics = _Diagnostics(src)
    h.assert_eq[USize](3, diagnostics.size())
    let tree = _ParseText(src)
    var errors: USize = 0
    for n in tree.nodes() do
      if n.kind() is NdError then
        errors = errors + 1
        var leaves: USize = 0
        for c in n.children() do
          if not c.is_trivia() then leaves = leaves + 1 end
        end
        h.assert_eq[USize](1, leaves, "an error node with " +
          leaves.string() + " tokens")
      end
    end
    h.assert_eq[USize](3, errors)
    for v in _Check(src).values() do h.fail(v.string()) end

class \nodoc\ iso _TestEveryKindIsDescribed is UnitTest
  fun name(): String => "parse/diagnostics: every token kind is described"

  fun apply(h: TestHelper) =>
    """
    A diagnostic names a found token by its text or by a description,
    never by its `Tk` name.
    """
    for kind in _AllTokenKinds().values() do
      let described = _Describe(kind)
      h.assert_ne[String](kind.name(), described)
      h.assert_false(described.at("Tk"), kind.name())
    end
