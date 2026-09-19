use "pony_test"

primitive \nodoc\ _RecoveryTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestUseThenUseKeepsBoth)
    test(_TestParenSweep)
    test(_TestEmptyGroupSweeps)
    test(_TestRefusalStopsAtTheNextItem)
    test(_TestRefusalStopsAtTheNextMethod)
    test(_TestEveryShapeSurvivesTheLimit)

primitive \nodoc\ _Tree
  """
  The tree assertions the recovery tests share: the tree reprints its
  source and `TreeCheck` is empty. One failure per tree at most, so
  that a sweep over thousands of trees costs no test-runner traffic
  when they pass.
  """
  fun sound(h: TestHelper, tree: SyntaxTree val, src: String val,
    label: String)
  =>
    if src != tree.reprint() then
      h.fail(label + ": reprint differs")
      return
    end
    try
      h.fail(label + ": " + TreeCheck(tree)(0)?.string())
    end

  fun depth_diagnostics(tree: SyntaxTree val): USize =>
    var n: USize = 0
    for d in tree.diagnostics.values() do
      if d.message.contains("grammar depth limit") then n = n + 1 end
    end
    n

  fun refused_region_starts_with_closer(tree: SyntaxTree val): Bool =>
    """
    Whether the `NdError` at the depth diagnostic's offset begins with
    a closing token. A refused region ends before a closer and never
    holds one. False when there is no such node: a refusal at a closer
    opens none.
    """
    var at: USize = 0
    for d in tree.diagnostics.values() do
      if d.message.contains("grammar depth limit") then at = d.offset end
    end
    for node in tree.nodes() do
      if (node.kind() is NdError) and (node.offset() == at) then
        for c in node.children() do
          match c.kind()
          | TkRparen | TkRsquare | TkRbrace | TkEnd => return true
          end
          break
        end
      end
    end
    false

class \nodoc\ iso _TestUseThenUseKeepsBoth is UnitTest
  fun name(): String => "parse/recovery: use then use keeps both"

  fun apply(h: TestHelper) =>
    """
    A `use` with no specifier followed by another `use` costs one
    diagnostic and nothing else: the recovery consumes nothing when the
    next token is one the section loop takes.
    """
    let src: String val = "use\nuse \"z\"\n"
    let tree = _ParseText(src)
    _Tree.sound(h, tree, src, "use use")
    h.assert_eq[USize](2, _Find.count(tree, NdUse))
    h.assert_eq[USize](0, _Find.count(tree, NdError))
    h.assert_eq[USize](1, tree.diagnostics.size())
    try
      h.assert_eq[USize](4, tree.diagnostics(0)?.offset)
    else
      h.fail("no diagnostic")
    end

class \nodoc\ iso _TestParenSweep is UnitTest
  fun name(): String => "parse/recovery: parentheses swept across the limit"

  fun apply(h: TestHelper) =>
    """
    For every depth of parentheses around a value from just under the
    limit to a few past it, with closers after: the tree is sound, at
    most one diagnostic names the depth limit, at least one depth is
    refused, and where one is the refused region does not begin with a
    closer, because it ends before the closer that the enclosing rule
    takes. The unmatched closers at the end land in an error node of
    their own; the check reads only the error node at the diagnostic's
    offset.
    """
    _Sweep(h, "(", "1", ")", "parens")

class \nodoc\ iso _TestEmptyGroupSweeps is UnitTest
  fun name(): String => "parse/recovery: empty groups swept"

  fun apply(h: TestHelper) =>
    """
    The same sweep with nothing inside the innermost group, for each
    closing token, so that at the limit the refusal falls on a closer:
    it must then open no error node at all.
    """
    _Sweep(h, "(", "", ")", "empty parens")
    _Sweep(h, "[", "", "]", "empty squares")
    _Sweep(h, "recover ", "", " end", "empty recovers")

primitive \nodoc\ _Sweep
  fun apply(h: TestHelper, opener: String, inner: String, closer: String,
    what: String)
  =>
    var refused: USize = 0
    var n: USize = 1240
    while n <= 1258 do
      let src: String val = _Nested.body(recover val
        opener.mul(n) + inner + closer.mul(n) end)
      let tree = _ParseText(src)
      let label: String val = n.string() + " " + what
      _Tree.sound(h, tree, src, label)
      let depth = _Tree.depth_diagnostics(tree)
      h.assert_true(depth <= 1, label + ": " + depth.string() +
        " depth diagnostics")
      if depth == 1 then
        refused = refused + 1
        h.assert_false(_Tree.refused_region_starts_with_closer(tree),
          label + ": the refused region begins with a closer")
      end
      n = n + 1
    end
    h.assert_true(refused > 0, what + ": no depth in the sweep was refused")

class \nodoc\ iso _TestRefusalStopsAtTheNextItem is UnitTest
  fun name(): String => "parse/recovery: a refusal stops at the next item"

  fun apply(h: TestHelper) =>
    """
    A region refused for depth with no closer after it ends at the next
    top-level keyword, whichever it is, so the item is kept and no error
    node holds its keyword.
    """
    // Two arrays rather than one of tuples: a tuple type holding a
    // token kind and a node kind takes ponyc minutes to check.
    let items: Array[String] = [
      "class D"; "actor D"; "primitive D"; "struct D"; "trait D"
      "interface D"; "type D is E"; "use \"z\""]
    let kinds: Array[TokenKind] = [
      TkClass; TkActor; TkPrimitive; TkStruct; TkTrait; TkInterface
      TkType; TkUse]
    h.assert_eq[USize](items.size(), kinds.size())
    for (i, keyword) in items.pairs() do
      let kind = try kinds(i)? else h.fail("no kind"); return end
      let src: String val = recover val
        "class C\n  fun f() => " + "(".mul(1500) + "\n" + keyword + "\n"
      end
      let tree = _ParseText(src)
      _Tree.sound(h, tree, src, keyword)
      h.assert_eq[USize](1, _Tree.depth_diagnostics(tree), keyword)
      if kind is TkUse then
        h.assert_eq[USize](1, _Find.count(tree, NdUse), keyword)
      else
        h.assert_eq[USize](2, _Find.count(tree, NdClassDef), keyword)
      end
      h.assert_false(_Holds(tree, NdError, kind),
        keyword + ": an error node holds the keyword")
    end

class \nodoc\ iso _TestRefusalStopsAtTheNextMethod is UnitTest
  fun name(): String => "parse/recovery: a refusal stops at the next method"

  fun apply(h: TestHelper) =>
    """
    A region refused for depth inside a method body ends at the next
    method start, whichever it is, so the method after it is kept.
    """
    // Two arrays for the same reason as in the test above.
    let items: Array[String] = ["fun g() => 1"; "be g() => 1"; "new g() => 1"]
    let kinds: Array[TokenKind] = [TkFun; TkBe; TkNew]
    h.assert_eq[USize](items.size(), kinds.size())
    for (i, keyword) in items.pairs() do
      let kind = try kinds(i)? else h.fail("no kind"); return end
      let src: String val = recover val
        "class C\n  fun f() => " + "(".mul(1500) + "\n  " + keyword + "\n"
      end
      let tree = _ParseText(src)
      _Tree.sound(h, tree, src, keyword)
      h.assert_eq[USize](1, _Tree.depth_diagnostics(tree), keyword)
      h.assert_eq[USize](2, _Find.count(tree, NdMethod), keyword)
      h.assert_false(_Holds(tree, NdError, kind),
        keyword + ": an error node holds the keyword")
    end

primitive \nodoc\ _Holds
  fun apply(tree: SyntaxTree val, node: NodeKind, leaf: TokenKind): Bool =>
    """
    Whether any node of kind `node` has a leaf of kind `leaf` anywhere
    beneath it.
    """
    for n in tree.nodes() do
      if n.kind() is node then
        let stop = n._index() + n._size()
        for m in tree.nodes() do
          if m._index() >= stop then break end
          if (m._index() > n._index()) and (m.kind() is leaf) then
            return true
          end
        end
      end
    end
    false

class \nodoc\ iso _TestEveryShapeSurvivesTheLimit is UnitTest
  fun name(): String => "parse/recovery: every shape survives the limit"

  fun apply(h: TestHelper) =>
    """
    One input per shape family, nested well past the limit: the
    nesting constructs `_Shapes` lists, the chains, and the token
    floods. Each must parse to a sound tree rather than crash. Each
    nesting construct is refused the number of times `_Shapes` records:
    once where the refused region runs to the end, and once per sibling
    region where the enclosing loop goes on to parse members or
    arguments at the limit; a changed count means a guard or a resync
    set moved. No chain is refused, since a chain does not descend.
    """
    for (label, src, refusals) in _Shapes(3000).values() do
      let tree = _ParseText(src)
      _Tree.sound(h, tree, src, label)
      h.assert_eq[USize](refusals, _Tree.depth_diagnostics(tree),
        label + ": depth refusals")
    end
    for (label, src) in _Shapes.chains(3000).values() do
      let tree = _ParseText(src)
      _Tree.sound(h, tree, src, label)
      h.assert_eq[USize](0, _Tree.depth_diagnostics(tree),
        label + ": a chain was refused for depth")
    end
    for (label, src) in _Shapes.floods(30_000).values() do
      let tree = _ParseText(src)
      _Tree.sound(h, tree, src, label)
    end

primitive \nodoc\ _Shapes
  """
  Sources nested `depth` deep, one per shape family, with the number of
  depth refusals each is parsed with: the openers of the nesting
  constructs listed here repeated `depth` times with no closers, inside
  a method body; the type-rule nestings inside a type alias; and,
  separately, the chains and the token floods.
  """
  fun apply(depth: USize): Array[(String, String val, USize)] =>
    let out = Array[(String, String val, USize)]
    for (label, opener, refusals) in
      [as (String, String, USize):
        ("paren", "(", 1); ("square", "[", 1)
        ("lambda", "{() => ", 1); ("bare lambda", "@{() => ", 1)
        ("lambda default", "{(x: A = ", 2)
        ("lambda capture", "{()(x = ", 1752)
        ("lambda type param", "{[A: ", 2)
        ("if", "if ", 2); ("ifdef", "ifdef ", 3); ("iftype", "iftype ", 3)
        ("while", "while ", 2); ("repeat", "repeat ", 2)
        ("for", "for x in ", 3); ("for tuple", "for (", 3)
        ("try", "try ", 1); ("match", "match ", 1)
        ("match object", "match x | object fun f(x: A = ", 1751)
        ("match ffi where", "match x | @f(where x = ", 1)
        ("recover", "recover ", 1)
        ("object", "object fun f(x: A = ", 1751); ("with", "with x = ", 3)
        ("prefix", "not ", 1); ("consume", "consume ", 1)
        ("assign", "x = ", 1); ("return", "return ", 1)
        ("call", "f(", 1); ("named call", "f(where a = ", 1)
        ("ffi call", "@f(", 1); ("constant", "F[#", 1)
        ("array", "[as A: ", 2)].values()
    do
      out.push((label, _body(opener.mul(depth)), refusals))
    end
    for (label, opener, refusals) in
      [as (String, String, USize):
        ("type args", "A[", 1); ("tuple type", "(A, ", 1)
        ("lambda type", "{(", 1); ("lambda type param default", "{[A = ", 2)
        ("viewpoint", "A->", 1); ("union", "(A | ", 1)].values()
    do
      out.push((label, _alias(opener.mul(depth)), refusals))
    end
    out

  fun chains(depth: USize): Array[(String, String val)] =>
    [as (String, String val):
      ("elseif", _body(recover val
        "if a then b " + "elseif a then b ".mul(depth) + "end" end))
      ("infix", _body(recover val "1" + " + 1".mul(depth) end))
      ("postfix", _body(recover val "x" + ".y".mul(depth) end))
      ("as", _body(recover val "x" + " as A".mul(depth) end))
      ("chain", _body(recover val "x" + ".>y()".mul(depth) end))
      ("statements", _body(recover val "x\n    ".mul(depth) end))
      ("members", recover val
        "class C\n" + "  fun f() => 1\n".mul(depth) end)
      ("entities", recover val "class C\n".mul(depth) end)
      ("uses", recover val "use \"a\"\n".mul(depth) end)
    ]

  fun floods(count: USize): Array[(String, String val)] =>
    [as (String, String val):
      ("top-level flood", recover val ")".mul(count) end)
      ("body flood", _body(recover val "end ".mul(count) end))
    ]

  fun _body(expr: String val): String val =>
    recover val "class C\n  fun f() =>\n    " + expr + "\n" end

  fun _alias(t: String val): String val =>
    recover val "type T is " + t + "\n" end
