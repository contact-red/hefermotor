use "pony_test"
use diag = "../diagnostics"
use source = "../source"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    _LexerTests.tests(test)
    _TokenKindTests.tests(test)
    _TreeTests.tests(test)
    _GrammarTests.tests(test)
    test(_TestBareUse)
    test(_TestSchemesAliasesAndGuards)
    test(_TestFfiExcluded)
    test(_TestDocstringSkipped)
    test(_TestCommentsAndBlankLines)
    test(_TestDuplicatesAndOrder)
    test(_TestDecodedLocator)
    test(_TestStopsAtFirstType)
    test(_TestUseDeclEquality)
    test(_TestEntryPointsAgree)
    test(_TestNoDiagnosticsWhenWellFormed)
    test(_TestGuardForms)
    test(_TestSeveralUsesOnOneLine)
    test(_TestMalformedUseSkipped)
    test(_TestStubStopsAtRestartToken)

primitive \nodoc\ _Uses
  fun apply(content: String): Array[UseDecl] val =>
    Parse.uses_only(source.SourceFile("/p", "a.pony", content))

  fun locators(content: String): Array[String] val =>
    let out = recover iso Array[String] end
    for u in apply(content).values() do out.push(u.locator) end
    consume out

  fun span(h: TestHelper, s: diag.Span, start: USize, length: USize,
    what: String)
  =>
    h.assert_eq[USize](start, s.start, what + " start")
    h.assert_eq[USize](length, s.length, what + " length")
    h.assert_eq[String]("/p", s.dir, what + " dir")
    h.assert_eq[String]("a.pony", s.name, what + " name")

class \nodoc\ iso _TestBareUse is UnitTest
  fun name(): String => "parse/uses: a bare use"

  fun apply(h: TestHelper) =>
    let uses = _Uses("use \"collections\"\n")
    h.assert_eq[USize](1, uses.size())
    try
      let u = uses(0)?
      h.assert_eq[String]("collections", u.locator)
      h.assert_true(u.alias is None)
      h.assert_true(u.guard is None)
      _Uses.span(h, u.span, 0, 17, "span")
      _Uses.span(h, u.locator_span, 4, 13, "locator span")
    else
      h.fail("no use")
    end

class \nodoc\ iso _TestSchemesAliasesAndGuards is UnitTest
  fun name(): String => "parse/uses: schemes, aliases and guards"

  fun apply(h: TestHelper) =>
    let uses = _Uses(
      "use \"package:net\"\n" +
      "use diag = \"../diagnostics\"\n" +
      "use \"lib:rt\" if linux\n" +
      "use \tfs   =  \"files\"\tif\tnot windows // why\n")
    h.assert_eq[USize](4, uses.size())
    try
      h.assert_eq[String]("package:net", uses(0)?.locator)
      h.assert_true(uses(0)?.alias is None)
      let aliased = uses(1)?
      h.assert_eq[String]("../diagnostics", aliased.locator)
      h.assert_eq[String]("diag", aliased.alias as String)
      h.assert_true(aliased.guard is None)
      // Line 2 starts at byte 18; the declaration is 27 bytes.
      _Uses.span(h, aliased.span, 18, 27, "aliased span")
      _Uses.span(h, aliased.locator_span, 29, 16, "aliased locator")
      let guarded = uses(2)?
      h.assert_eq[String]("lib:rt", guarded.locator)
      // Line 3 starts at byte 46: `use "lib:rt" if linux`.
      _Uses.span(h, guarded.guard as diag.Span, 62, 5, "guard")
      _Uses.span(h, guarded.span, 46, 21, "guarded span")
      _Uses.span(h, guarded.locator_span, 50, 8, "guarded locator")
      let spaced = uses(3)?
      h.assert_eq[String]("files", spaced.locator)
      h.assert_eq[String]("fs", spaced.alias as String)
      // Line 4 starts at byte 68; the guard is `not windows`, and neither
      // the blank after it nor the comment is part of it.
      _Uses.span(h, spaced.guard as diag.Span, 92, 11, "spaced guard")
      _Uses.span(h, spaced.span, 68, 35, "spaced span")
      let end_guard = _Uses("use \"a\" if ")
      h.assert_eq[USize](1, end_guard.size())
    else
      h.fail("four uses expected")
    end

class \nodoc\ iso _TestFfiExcluded is UnitTest
  """
  FFI declarations are not `UseDecl`s, including one whose guard
  continues on the next line, and a package `use` after them is still
  found.
  """
  fun name(): String => "parse/uses: FFI declarations are excluded"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[String](["collections"], _Uses.locators(
      "use @open[I32](path: Pointer[U8] tag, flags: I32, ...) if windows\n" +
      "use @read[ISize](fd: I32, buffer: Pointer[None], n: USize)\n" +
      "  if not windows\n" +
      "use @pony_os_errno[I32]()\n" +
      "\n" +
      "use \"collections\"\n"))

class \nodoc\ iso _TestDocstringSkipped is UnitTest
  """
  The package docstring is the module's first token, so a `use` inside
  it is not a `use`, and neither is one inside a docstring delimited by
  one `"`; the docstring is still skipped after a `//` header.
  """
  fun name(): String => "parse/uses: a leading docstring is skipped"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[String](["random"; "time"], _Uses.locators(
      "\"\"\"\n" +
      "# pony_test\n" +
      "\n" +
      "use bar = \"bar\"\n" +
      "use foo = \"foo\"\n" +
      "\"\"\"\n" +
      "\n" +
      "use \"random\"\n" +
      "use \"time\"\n"))
    h.assert_array_eq[String](["net"], _Uses.locators(
      "// Copyright header.\n" +
      "// Second line.\n" +
      "\n" +
      "\"A one-line docstring with use \\\"x\\\" in it.\"\n" +
      "use \"net\"\n"))
    h.assert_array_eq[String](["a"], _Uses.locators(
      "\"\"\"one line\"\"\"\nuse \"a\"\n"))

class \nodoc\ iso _TestCommentsAndBlankLines is UnitTest
  fun name(): String => "parse/uses: comments and blank lines are skipped"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[String](["a"; "b"], _Uses.locators(
      "\n\n// a comment\nuse \"a\"\n\n  // indented comment\n\nuse \"b\"\n"))

class \nodoc\ iso _TestDuplicatesAndOrder is UnitTest
  fun name(): String => "parse/uses: duplicates kept, source order"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[String](["b"; "a"; "b"], _Uses.locators(
      "use \"b\"\nuse \"a\"\nuse \"b\"\n"))

class \nodoc\ iso _TestDecodedLocator is UnitTest
  """
  The locator is the decoded string, so an escaped quote or backslash in
  the literal is one character in the locator, and the literal's span
  still covers the written text.
  """
  fun name(): String => "parse/uses: the locator is decoded"

  fun apply(h: TestHelper) =>
    let uses = _Uses("use \"a\\\\b\\\"c\"\n")
    try
      h.assert_eq[String]("a\\b\"c", uses(0)?.locator)
      _Uses.span(h, uses(0)?.locator_span, 4, 9, "literal")
    else
      h.fail("one use expected")
    end

class \nodoc\ iso _TestStopsAtFirstType is UnitTest
  fun name(): String => "parse/uses: a use after a type is excluded"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[String](["a"], _Uses.locators(
      "use \"a\"\n\nclass Foo\n  fun apply() => None\n\nuse \"b\"\n"))
    h.assert_array_eq[String](["a"], _Uses.locators(
      "use \"a\"\nactor Main\n  new create(env: Env) => None\nuse \"b\"\n"))

class \nodoc\ iso _TestUseDeclEquality is UnitTest
  fun name(): String => "parse/uses: equality compares every field"

  fun apply(h: TestHelper) =>
    let sp = diag.Span("/p", "a.pony", 0, 7)
    let ls = diag.Span("/p", "a.pony", 4, 3)
    let g = diag.Span("/p", "a.pony", 11, 5)
    let base = UseDecl("a", None, None, sp, ls)
    h.assert_true(base == UseDecl("a", None, None, sp, ls))
    h.assert_false(base == UseDecl("b", None, None, sp, ls))
    h.assert_false(base == UseDecl("a", "x", None, sp, ls))
    h.assert_false(base == UseDecl("a", None, g, sp, ls))
    h.assert_false(base == UseDecl("a", None, None, g, ls))
    h.assert_false(base == UseDecl("a", None, None, sp, g))
    h.assert_true(UseDecl("a", "x", g, sp, ls)
      == UseDecl("a", "x", g, sp, ls))
    h.assert_false(UseDecl("a", "x", g, sp, ls)
      == UseDecl("a", "y", g, sp, ls))
    h.assert_false(UseDecl("a", "x", g, sp, ls)
      == UseDecl("a", "x", diag.Span("/p", "a.pony", 11, 6), sp, ls))

class \nodoc\ iso _TestEntryPointsAgree is UnitTest
  """
  `Parse(file).uses` and `Parse.uses_only(file)` agree element by
  element. `apply` takes its `uses` from `uses_only`, so this test
  cannot fail until `apply` reads them from the tree. Its M1 inputs are
  the ponyc `packages/` tree and the broken-file corpus.
  """
  fun name(): String => "parse/uses: the two entry points agree"

  fun apply(h: TestHelper) =>
    let content =
      "\"\"\"\ndoc\n\"\"\"\nuse \"a\"\nuse x = \"b\" if linux\n" +
      "use @f[I32]()\nclass C\nuse \"c\"\n"
    let file = source.SourceFile("/p", "a.pony", content)
    let whole = Parse(file)
    let section = Parse.uses_only(file)
    h.assert_eq[USize](section.size(), whole.uses.size())
    h.assert_eq[USize](2, section.size())
    var i: USize = 0
    while i < section.size() do
      try
        h.assert_true(section(i)? == whole.uses(i)?, "use " + i.string())
      else
        h.fail("index " + i.string())
      end
      i = i + 1
    end
    h.assert_true(whole.file is file)

class \nodoc\ iso _TestNoDiagnosticsWhenWellFormed is UnitTest
  """
  `apply` drops what the parser records, so this test cannot fail until
  `apply` reports diagnostics. It holds the contract's last clause:
  well-formed input produces no diagnostics.
  """
  fun name(): String => "parse/apply: no diagnostics on well-formed input"

  fun apply(h: TestHelper) =>
    let parsed = Parse(source.SourceFile("/p", "a.pony",
      "use \"a\"\n\nactor Main\n  new create(env: Env) => None\n"))
    h.assert_eq[USize](0, parsed.diagnostics.size())
    h.assert_eq[USize](1, parsed.uses.size())

class \nodoc\ iso _TestStubStopsAtRestartToken is UnitTest
  """
  The scanner stops at the first line whose first token opens a type
  definition and skips every other non-`use` line, so `typedef` does not
  end the section. Deleted with the scanner.
  """
  fun name(): String => "parse/stub: stops at the first type keyword"

  fun apply(h: TestHelper) =>
    let keywords: Array[String] val =
      ["type"; "interface"; "trait"; "primitive"; "struct"; "class"
       "actor"]
    for keyword in keywords.values() do
      h.assert_array_eq[String](["a"], _Uses.locators(
        "use \"a\"\n" + keyword + " T\nuse \"b\"\n"), keyword)
    end
    h.assert_array_eq[String](["a"; "b"], _Uses.locators(
      "use \"a\"\ntypedef T\nuse \"b\"\n"))

class \nodoc\ iso _TestGuardForms is UnitTest
  """
  A guard follows `if` and any non-identifier byte: a blank, a `(`, or
  the end of the line, in which case the guard is the next line.
  """
  fun name(): String => "parse/uses: guard forms"

  fun apply(h: TestHelper) =>
    let uses = _Uses(
      "use \"a\" if(linux)\n" +
      "use \"b\" if\n" +
      "  windows\n" +
      "use \"c\" if \n" +
      "  osx or bsd\n" +
      "use \"d\" ifx\n")
    h.assert_eq[USize](4, uses.size())
    try
      _Uses.span(h, uses(0)?.guard as diag.Span, 10, 7, "paren guard")
      _Uses.span(h, uses(0)?.span, 0, 17, "paren span")
      // `use "b" if` is 10 bytes from 18; the guard sits on the next
      // line at byte 31.
      _Uses.span(h, uses(1)?.guard as diag.Span, 31, 7, "next-line guard")
      _Uses.span(h, uses(1)?.span, 18, 20, "next-line span")
      _Uses.span(h, uses(2)?.guard as diag.Span, 53, 10, "spaced guard")
      h.assert_true(uses(3)?.guard is None)
      _Uses.span(h, uses(3)?.span, 64, 7, "ifx span")
    else
      h.fail("four uses expected")
    end

class \nodoc\ iso _TestSeveralUsesOnOneLine is UnitTest
  fun name(): String => "parse/uses: several uses on one line"

  fun apply(h: TestHelper) =>
    let uses = _Uses("use \"a\" use \"b\" if linux use c = \"d\"\n")
    h.assert_array_eq[String](["a"; "b"; "d"],
      _Uses.locators("use \"a\" use \"b\" if linux use c = \"d\"\n"))
    try
      h.assert_true(uses(0)?.guard is None)
      _Uses.span(h, uses(0)?.span, 0, 7, "first span")
      _Uses.span(h, uses(1)?.guard as diag.Span, 19, 5, "second guard")
      _Uses.span(h, uses(1)?.span, 8, 16, "second span")
      h.assert_eq[String]("c", uses(2)?.alias as String)
      _Uses.span(h, uses(2)?.span, 25, 11, "third span")
    else
      h.fail("three uses expected")
    end
    h.assert_array_eq[String](["a"; "b"],
      _Uses.locators("use \"a\"\ruse \"b\"\r"))

class \nodoc\ iso _TestMalformedUseSkipped is UnitTest
  """
  A line that says `use` but does not fit `use [alias =] "locator" [if
  guard]` yields no declaration and does not end the section.
  """
  fun name(): String => "parse/uses: a malformed use is skipped"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[String](["z"], _Uses.locators(
      "use = \"a\"\n" +
      "use x \"b\"\n" +
      "use \"c\n" +
      "use \"\"\"d\"\"\"\n" +
      "use\n" +
      "use \"z\"\n"))
