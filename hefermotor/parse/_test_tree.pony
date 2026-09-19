use "collections"
use "itertools"
use "pony_test"
use diag = "../diagnostics"
use source = "../source"
primitive \nodoc\ _TreeTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestReprintsTheSource)
    test(_TestShape)
    test(_TestTriviaBelongToTheEnclosingNode)
    test(_TestTreeCheckEmptyOverFixtures)
    test(_TestTreeCheckRows)
    test(_TestTreeCheckErrorRows)
    test(_TestErrorIsBounded)
    test(_TestErrorAtTheStart)
    test(_TestDiagnosticsAreRecorded)
    test(_TestEveryTruncationReprints)
    test(_TestPathToEveryByte)
    test(_TestPathToTheEnd)
    test(_TestNodeViews)
    test(_TestNodesInPreOrder)
    test(_TestNodeEquality)
    test(_TestElementsArePlain)

primitive \nodoc\ _ParseText
  """
  Parses a source as a file named `test.pony` in `/test`.
  """
  fun apply(src: String val): SyntaxTree val =>
    Parse.tree(_TestFile(src))

primitive \nodoc\ _Diagnostics
  """
  What the parser reports over a source, sorted as `ParsedFile` sorts
  it.
  """
  fun apply(src: String val): Array[diag.Diagnostic] val =>
    Parse(_TestFile(src)).diagnostics

primitive \nodoc\ _Check
  """
  `TreeCheck` over a source's tree and diagnostics.
  """
  fun apply(src: String val): Array[TreeViolation] val =>
    TreeCheck(_ParseText(src), _Diagnostics(src))

primitive \nodoc\ _TestFile
  fun apply(src: String val): source.SourceFile =>
    source.SourceFile("/test", "test.pony", src)

primitive \nodoc\ _Start
  """
  The byte offset a diagnostic starts at; `USize.max_value()` for one
  not located at a span.
  """
  fun apply(d: diag.Diagnostic): USize =>
    match d.location
    | let s: diag.Span => s.start
    else
      USize.max_value()
    end

primitive \nodoc\ _Shape
  fun apply(tree: SyntaxTree val): String val =>
    """
    The tree as nested kind names, so a test can assert on structure in one
    readable string rather than by walking indices.
    """
    let out = recover String end
    let ends = Array[USize]
    for node in tree.nodes() do
      let index = node._index()
      while try ends(ends.size() - 1)? <= index else false end do
        try ends.pop()? end
      end
      if index > 0 then out.append(" ") end
      var d = ends.size()
      while d > 0 do
        out.append(">")
        d = d - 1
      end
      out.append(node.kind().name())
      if not node.is_leaf() then ends.push(index + node._size()) end
    end
    consume out

class \nodoc\ iso _TestReprintsTheSource is UnitTest
  fun name(): String => "parse/tree: reprints the source"

  fun apply(h: TestHelper) =>
    """
    Losslessness at the tree level rather than the token level: the leaves
    tile the source, so concatenating them gives it back.
    """
    for src in _Fixtures().values() do
      let tree = _ParseText(src)
      h.assert_eq[String](src, tree.reprint(),
        "reprint differs for: " + src)
    end

primitive \nodoc\ _Fixtures
  """
  Sources the tree tests share: clean, broken, empty, trivia only.
  """
  fun apply(): Array[String val] =>
    [ ""
      "use \"collections\""
      "\"\"\"A docstring\"\"\"\nuse \"time\"\n\nclass Foo\n  let x: U32\n"
      "// only a comment\n"
      "// only a comment"
      "class Foo\n\nactor Bar\n\nprimitive Baz\n"
      "use collections = \"collections\"\n"
      "$$$ garbage $$$\n"
      "!!!\n"
      "\nclass Foo\n"
      "  \nclass Foo\n"
      "/* leading */ class Foo\n"
      "\n\n\n"
      "class Foo\n\n\n"
      "use \"a\"\n// trailing comment\n"
      "class Foo\n  fun f() =>\n    /* nested /* comment */ */\n    1\n"
      "use 12345\nclass Foo\n"
      "class Foo\n  fun f() =>\n    ?? ]] => a\n"
      "actor Main\n  new create(env: Env) =>\n    env.out.print(\"hi\")\n"
      "trait T\n  fun f(): U8\nclass \\nodoc\\ C is T\n  fun f(): U8 => 1\n"
    ]

class \nodoc\ iso _TestShape is UnitTest
  fun name(): String => "parse/tree: shape"

  fun apply(h: TestHelper) =>
    h.assert_eq[String](
      "NdModule >NdUse >>TkUse >>TkWhitespace >>TkString >TkEof",
      _Shape(_ParseText("use \"collections\"")))

class \nodoc\ iso _TestTriviaBelongToTheEnclosingNode is UnitTest
  fun name(): String => "parse/tree: trivia belong to the enclosing node"

  fun apply(h: TestHelper) =>
    """
    Whitespace between two items belongs to what contains them, not to
    whichever item happens to follow. `start` flushes pending trivia before
    it opens a node, which is what puts them there.
    """
    let tree = _ParseText("class A\n\nclass B\n")
    // The blank line between the two classes is a child of the module, and
    // so is the trailing newline, because an item stops at the token that
    // starts the next one and never consumes the trivia between.
    var module_children: USize = 0
    var kinds = recover String end
    for c in tree.root().children() do
      module_children = module_children + 1
      kinds.append(c.kind().name())
      kinds.append(" ")
    end
    h.assert_eq[String](
      "NdClassDef TkWhitespace NdClassDef TkWhitespace TkEof ", consume kinds)
    h.assert_eq[USize](5, module_children)
    // And the class does not swallow the blank line after it, which would
    // make its fold range a line too long.
    match tree.root().child(NdClassDef)
    | let c: Node => h.assert_eq[String]("class A", c.text())
    | None => h.fail("no first class")
    end

class \nodoc\ iso _TestTreeCheckEmptyOverFixtures is UnitTest
  fun name(): String => "parse/tree: TreeCheck is empty over every fixture"

  fun apply(h: TestHelper) =>
    for src in _Fixtures().values() do
      for v in _Check(src).values() do
        h.fail(v.string() + " for: " + src)
      end
    end
    let big = recover val
      let out = String
      for src in _Fixtures().values() do out.append(src) end
      out
    end
    for v in _Check(big).values() do
      h.fail(v.string() + " for the joined fixture")
    end

class \nodoc\ iso _TestTreeCheckRows is UnitTest
  fun name(): String =>
    "parse/tree: each TreeCheck invariant fires on its fault"

  fun apply(h: TestHelper) =>
    """
    One counterfactual per row, built through `_create` from a sound
    tree's elements with one element changed, each asserting the exact
    violations reported.
    """
    let file = source.SourceFile("/t", "t.pony", "use \"a\"\n")
    let sound = Parse.tree(file)
    // Elements: NdModule(0, 7), NdUse(0, 4), TkUse@0, TkWhitespace@3,
    // TkString@4, TkWhitespace@7, TkEof@8. Widths are derived, so a
    // size or an offset can only move bytes between neighbours, never
    // lose them: a shrunken NdUse leaves its string a child of the
    // module, which is consistent, and a leaf moved forward widens the
    // leaf before it.
    h.assert_eq[String](
      "NdModule >NdUse >>TkUse >>TkWhitespace >>TkString >TkWhitespace >TkEof",
      _Shape(sound))
    let cases: Array[(String, USize, SyntaxElement, String)] = [
      ("root too small", 0, (NdModule, 0, 6), "OneRoot at element 0")
      ("no eof", 6, (TkId, 8, 1), "EofLast at element 6")
      ("eof early", 6, (TkEof, 7, 1), "EofLast at element 6")
      ("use past the end", 1, (NdUse, 0, 8),
        "SubtreeSizes at element 1, SubtreeSizes at element 0")
      ("use empty", 1, (NdUse, 0, 0),
        "SubtreeSizes at element 1, SubtreeSizes at element 0")
      ("offset back", 4, (TkString, 2, 1), "OffsetsMonotone at element 4")
      ("use starts late", 1, (NdUse, 1, 4),
        "FirstLeafOffset at element 0, OffsetsMonotone at element 2, " +
        "FirstLeafOffset at element 1")
      ("empty node off its place", 3, (NdSeq, 3, 1),
        "FirstLeafOffset at element 3, Reprint at element 4")
      ("root not a module", 0, (NdSeq, 0, 7), "OneRoot at element 0")
      ("leaf sized two", 2, (TkUse, 0, 2),
        "SubtreeSizes at element 2, Reprint at element 3, " +
        "SubtreeSizes at element 1")
      ("interior last", 6, (NdSeq, 7, 1),
        "EofLast at element 6, FirstLeafOffset at element 6, " +
        "Reprint at element 6")
    ]
    for (label, at, element, expected) in cases.values() do
      let elems = recover iso Array[SyntaxElement] end
      for (i, e) in sound._elements().pairs() do
        elems.push(if i == at then element else e end)
      end
      _check(h, file, consume elems, expected, label)
    end
    // Every element but the end token starts three bytes late: the
    // file's first three bytes are covered by nothing, and the end
    // token's offset is now below the whitespace's before it.
    let shifted = recover iso Array[SyntaxElement] end
    for (k, o, n) in sound._elements().values() do
      shifted.push(if k is TkEof then (k, o, n) else (k, o + 3, n) end)
    end
    _check(h, file, consume shifted,
      "Reprint at element 2, OffsetsMonotone at element 6",
      "every leaf shifted")
    _check(h, file, recover val Array[SyntaxElement] end,
      "OneRoot at element 0, EofLast at element 0", "no elements")

  fun _check(h: TestHelper, file: source.SourceFile,
    elems: Array[SyntaxElement] val, expected: String, label: String)
  =>
    let broken = SyntaxTree._create(file, elems)
    let got: String val = ", ".join(
      Iter[TreeViolation](
        TreeCheck(broken, recover val Array[diag.Diagnostic] end).values())
        .map[String]({(v) => v.string() }))
    h.assert_eq[String](expected, got, label)

class \nodoc\ iso _TestTreeCheckErrorRows is UnitTest
  fun name(): String =>
    "parse/tree: each TreeCheck error and diagnostic row fires on its fault"

  fun apply(h: TestHelper) =>
    """
    Hand-built trees and diagnostic lists, one per row: the sound form
    passes and the faulty form reports exactly the row.
    """
    let expected = {(at: USize): diag.Diagnostic =>
      diag.Diagnostic(SyntaxExpected("x", TkId),
        diag.Span("/t", "t.pony", at, 0)) } val
    let nesting = {(at: USize): diag.Diagnostic =>
      diag.Diagnostic(NestingTooDeep("x", 2500),
        diag.Span("/t", "t.pony", at, 1)) } val
    let limit = diag.Diagnostic(SyntaxLimit(500),
      diag.FileOnly("/t", "t.pony"))
    let refused = diag.Diagnostic(LexError(UnrecognizedCharacter('$')),
      diag.Span("/t", "t.pony", 0, 1))
    // An error node holding one identifier, under the module.
    let sound: Array[SyntaxElement] val =
      [(NdModule, 0, 5); (NdError, 0, 2); (TkId, 0, 1); (TkWhitespace, 1, 1)
        (TkEof, 2, 1)]
    _check2(h, "x\n", sound, [expected(0)], "", "sound error node")
    _check2(h, "x\n", sound, [], "ErrorAtDiagnostic at element 1",
      "no diagnostic at the error")
    _check2(h, "x\n", sound, [limit], "", "the limit stands in")
    _check2(h, "x\n", sound, [expected(1)],
      "ErrorAtDiagnostic at element 1", "a diagnostic elsewhere")
    _check2(h, "x\n",
      [(NdModule, 0, 6); (NdError, 0, 3); (NdSeq, 0, 2); (TkId, 0, 1)
        (TkWhitespace, 1, 1); (TkEof, 2, 1)],
      [expected(0)], "ErrorLeafOnly at element 1", "a node in an error")
    _check2(h, " \n",
      [(NdModule, 0, 4); (NdError, 0, 2); (TkWhitespace, 0, 1)
        (TkEof, 2, 1)],
      [expected(0)], "ErrorNonEmpty at element 1", "trivia only")
    let refusal_first: Array[SyntaxElement] val =
      [(NdModule, 0, 5); (NdError, 0, 2); (TkLexError, 0, 1)
        (TkWhitespace, 1, 1); (TkEof, 2, 1)]
    _check2(h, "$\n", refusal_first, [refused], "",
      "a lexer refusal's record excuses its error node")
    _check2(h, "$\n", refusal_first, [], "ErrorAtDiagnostic at element 1",
      "a lexer refusal with no record")
    // An error node under an entity: only a nesting record excuses it.
    let under_entity: Array[SyntaxElement] val =
      [(NdModule, 0, 8); (NdClassDef, 0, 6); (TkClass, 0, 1)
        (TkWhitespace, 5, 1); (NdError, 6, 2); (TkId, 6, 1)
        (TkWhitespace, 7, 1); (TkEof, 8, 1)]
    _check2(h, "class C\n", under_entity, [expected(6)],
      "ErrorParent at element 4", "an error under an entity")
    _check2(h, "class C\n", under_entity, [nesting(6)], "",
      "a refused region under an entity")
    _check2(h, "class\n",
      [(NdModule, 0, 5); (NdError, 0, 2); (TkClass, 0, 1)
        (TkWhitespace, 5, 1); (TkEof, 6, 1)],
      [expected(0)], "ErrorNoEntity at element 1", "an entity keyword")
    _check2(h, "class C\n fun\n",
      [(NdModule, 0, 11); (NdClassDef, 0, 8); (TkClass, 0, 1)
        (TkWhitespace, 5, 1); (TkId, 6, 1); (TkWhitespace, 7, 1)
        (NdMembers, 9, 3); (NdError, 9, 2); (TkFun, 9, 1)
        (TkWhitespace, 12, 1); (TkEof, 13, 1)],
      [expected(9)], "ErrorNoMemberStart at element 7",
      "a method start in a member list's error")
    _check2(h, "use\n",
      [(NdModule, 0, 5); (NdError, 0, 2); (TkUse, 0, 1)
        (TkWhitespace, 3, 1); (TkEof, 4, 1)],
      [expected(0)], "ErrorNoUseInSection at element 1",
      "a use in the section's error")
    _check2(h, "class C\nuse\n",
      [(NdModule, 0, 10); (NdClassDef, 0, 5); (TkClass, 0, 1)
        (TkWhitespace, 5, 1); (TkId, 6, 1); (TkWhitespace, 7, 1)
        (NdError, 8, 2); (TkUse, 8, 1); (TkWhitespace, 11, 1)
        (TkEof, 12, 1)],
      [expected(8)], "", "a use after an entity is not in the section")
    _check2(h, "x\n", sound, [expected(0); expected(9)],
      "DiagnosticInFile at diagnostic 1", "a span past the end")
    _check2(h, "x\n", sound,
      [expected(0); diag.Diagnostic(SyntaxExpected("x", TkId),
        diag.Span("/t", "other.pony", 0, 0))],
      "DiagnosticInFile at diagnostic 1, DiagnosticsOrdered at " +
      "diagnostic 1", "another file, which also sorts before this one")
    _check2(h, "x\n", sound, [expected(1); expected(0)],
      "DiagnosticsOrdered at diagnostic 1", "out of order")

  fun _check2(h: TestHelper, src: String val, elems: Array[SyntaxElement] val,
    diagnostics: Array[diag.Diagnostic] val, expected: String, label: String)
  =>
    let tree = SyntaxTree._create(source.SourceFile("/t", "t.pony", src),
      elems)
    let got: String val = ", ".join(
      Iter[TreeViolation](TreeCheck(tree, diagnostics).values())
        .map[String]({(v) => v.string() }))
    h.assert_eq[String](expected, got, label)

class \nodoc\ iso _TestErrorIsBounded is UnitTest
  fun name(): String => "parse/tree: an error costs one item"

  fun apply(h: TestHelper) =>
    """
    The point of recovery: a `use` that does not parse must not take the
    class after it with it.
    """
    let src = "use 12345\nclass Foo\n"
    let tree = _ParseText(src)
    h.assert_eq[String](src, tree.reprint())
    h.assert_ne[USize](0, _Find.count(tree, NdError), "no error node")
    h.assert_eq[USize](1, _Find.count(tree, NdClassDef),
      "the class after the bad use was lost")

class \nodoc\ iso _TestErrorAtTheStart is UnitTest
  fun name(): String => "parse/tree: junk before the first item"

  fun apply(h: TestHelper) =>
    let src = "!!! \nclass Foo\n"
    let tree = _ParseText(src)
    h.assert_eq[String](src, tree.reprint())
    h.assert_eq[USize](1, _Find.count(tree, NdClassDef),
      "recovery did not reach the class")

class \nodoc\ iso _TestDiagnosticsAreRecorded is UnitTest
  fun name(): String => "parse/tree: diagnostics are recorded"

  fun apply(h: TestHelper) =>
    let diagnostics = _Diagnostics("use 12345\n")
    h.assert_ne[USize](0, diagnostics.size(), "no diagnostic")
    try
      let d = diagnostics(0)?
      h.assert_true(_Start(d) <= "use 12345\n".size(),
        "diagnostic offset out of range")
    else
      h.fail("no diagnostic")
    end

class \nodoc\ iso _TestEveryTruncationReprints is UnitTest
  fun name(): String => "parse/tree: every truncation reprints"

  fun apply(h: TestHelper) =>
    """
    Error tolerance at the tree level, exhaustively: cutting a source at any
    byte must still produce a tree that reprints to it and passes
    `TreeCheck`.
    """
    let src =
      "\"\"\"Docstring\"\"\"\n" +
      "use \"collections\"\n" +
      "use c = \"time\"\n" +
      "class Foo\n" +
      "  let x: U32 = 1\n" +
      "actor Bar\n" +
      "  be go() =>\n" +
      "    None\n"
    var cut: USize = 0
    while cut <= src.size() do
      let piece = recover val src.substring(0, cut.isize()) end
      let tree = _ParseText(piece)
      h.assert_eq[String](piece, tree.reprint(),
        "reprint differs at cut " + cut.string())
      for v in TreeCheck(tree, _Diagnostics(piece)).values() do
        h.fail(v.string() + " at cut " + cut.string())
      end
      cut = cut + 1
    end

class \nodoc\ iso _TestPathToEveryByte is UnitTest
  fun name(): String => "parse/tree: path_to at every byte"

  fun apply(h: TestHelper) =>
    """
    At every byte of a fixture the path nests, starts at the root, and
    ends at a leaf covering the byte.
    """
    for src in _Fixtures().values() do
      let tree = _ParseText(src)
      var byte: USize = 0
      while byte < src.size() do
        let path = tree.path_to(byte)
        let label = "byte " + byte.string() + " of: " + src
        try
          h.assert_true(path(0)? == tree.root(), label + ": not the root")
          let last = path(path.size() - 1)?
          h.assert_true(last.is_leaf(), label + ": not a leaf")
          h.assert_true((last.offset() <= byte) and (byte < last.finish()),
            label + ": the leaf does not cover the byte")
          var i: USize = 1
          while i < path.size() do
            let outer = path(i - 1)?
            let inner = path(i)?
            h.assert_true((outer.offset() <= inner.offset()) and
              (inner.finish() <= outer.finish()), label + ": no nesting")
            i = i + 1
          end
        else
          h.fail(label + ": empty path")
        end
        byte = byte + 1
      end
    end

class \nodoc\ iso _TestPathToTheEnd is UnitTest
  fun name(): String => "parse/tree: path_to at and past the end"

  fun apply(h: TestHelper) =>
    let src: String val = "use \"a\"\n"
    let tree = _ParseText(src)
    try
      let at_end = tree.path_to(src.size())
      h.assert_true(at_end(at_end.size() - 1)?.kind() is TkEof,
        "the path to the size does not end at TkEof")
    else
      h.fail("no path to the size")
    end
    h.assert_eq[USize](0, tree.path_to(src.size() + 1).size())
    let empty = _ParseText("")
    let path = empty.path_to(0)
    h.assert_eq[USize](2, path.size())
    try
      h.assert_true(path(0)?.kind() is NdModule)
      h.assert_true(path(1)?.kind() is TkEof)
    end

class \nodoc\ iso _TestNodeViews is UnitTest
  fun name(): String => "parse/tree: a node's text, span, trivia and children"

  fun apply(h: TestHelper) =>
    """
    `is_trivia` is true for exactly the whitespace and comment leaves;
    `span` names the file; every leaf's text concatenated is the source
    and the non-trivia leaves' is the source without its trivia;
    `child` and `first_token` on an entity with and without
    annotations, and `first_token` on a node whose first child is a
    node.
    """
    let src: String val =
      "// c\nclass \\a\\ A\n  fun f() => /* n */ x.y + 1\n\nactor B\n"
    let file = source.SourceFile("/pkg", "m.pony", src)
    let tree = Parse.tree(file)
    let all = recover iso String end
    let significant = recover iso String end
    var trivia: USize = 0
    for node in tree.nodes() do
      if node.is_leaf() then
        all.append(node.text())
        if node.is_trivia() then
          trivia = trivia + 1
          h.assert_true(
            match node.kind()
            | TkWhitespace | TkLineComment | TkNestedComment => true
            else
              false
            end, "trivia of kind " + node.kind().name())
        else
          significant.append(node.text())
        end
      else
        h.assert_false(node.is_trivia(), node.kind().name() + " is trivia")
      end
    end
    h.assert_eq[String](src, consume all)
    h.assert_eq[String]("class\\a\\Afunf()=>x.y+1actorB",
      consume significant)
    h.assert_eq[USize](15, trivia)
    match tree.root().child(NdClassDef)
    | let a: Node =>
      var found = false
      for n in tree.nodes() do
        if (n.kind() is NdBinOp) and (n.offset() >= a.offset()) then
          found = true
          h.assert_true(n.first_token() is TkPlus,
            "the operator is the first leaf child of the infix node")
          break
        end
      end
      h.assert_true(found, "no infix node")
    | None => h.fail("no class")
    end
    let entities = Array[Node]
    for c in tree.root().children() do
      if c.kind() is NdClassDef then entities.push(c) end
    end
    h.assert_eq[USize](2, entities.size())
    try
      let a = entities(0)?
      h.assert_true(a.span() == diag.Span("/pkg", "m.pony", 5, 40),
        "span " + a.span().start.string() + "+" + a.span().length.string())
      h.assert_true(a.first_token() is TkClass)
      match a.child(NdAnnotations)
      | let ann: Node => h.assert_eq[String]("\\a\\", ann.text())
      | None => h.fail("no annotations")
      end
      match a.child(TkId)
      | let id: Node => h.assert_eq[String]("A", id.text())
      | None => h.fail("no name")
      end
      let b = entities(1)?
      h.assert_true(b.first_token() is TkActor)
      h.assert_true(b.child(NdAnnotations) is None)
      h.assert_eq[String]("actor B", b.text())
    end

class \nodoc\ iso _TestNodesInPreOrder is UnitTest
  fun name(): String => "parse/tree: nodes visits every element in order"

  fun apply(h: TestHelper) =>
    let tree = _ParseText("use \"a\"\nclass Foo\n  fun f() => 1\n")
    var expected: USize = 0
    for node in tree.nodes() do
      h.assert_eq[USize](expected, node._index())
      expected = expected + 1
    end
    h.assert_eq[USize](tree.size(), expected)

class \nodoc\ iso _TestNodeEquality is UnitTest
  fun name(): String => "parse/tree: nodes are equal within one tree only"

  fun apply(h: TestHelper) =>
    let src: String val = "class Foo\n"
    let once = _ParseText(src)
    let again = _ParseText(src)
    h.assert_true(once.root() == once.root())
    h.assert_false(once.root() == again.root())
    try
      h.assert_false(once.root() == once._node(1)?)
    else
      h.fail("no element 1")
    end

class \nodoc\ iso _TestElementsArePlain is UnitTest
  fun name(): String => "parse/tree: an element is a kind and two U32s"

  fun apply(h: TestHelper) =>
    """
    Pins the element type: a primitive union and two `U32`s, so that a
    `val` send of a tree traces none of its elements.
    """
    let tree = _ParseText("")
    let e: Array[(SyntaxKind, U32, U32)] val = tree._elements()
    h.assert_eq[USize](2, e.size())
