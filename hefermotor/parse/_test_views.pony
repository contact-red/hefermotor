use "pony_test"
use "itertools"
use diag = "../diagnostics"
use source = "../source"

primitive \nodoc\ _ViewTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestTreeViews)
    test(_TestPackageUseView)
    test(_TestFfiDeclView)
    test(_TestEntityView)
    test(_TestFieldView)
    test(_TestMethodView)
    test(_TestMethodDocstringRule)
    test(_TestParamViews)
    test(_TestTypeOfForms)
    test(_TestTypeOfFolds)
    test(_TestMembersHoldingAnError)
    test(_TestViewRows)

primitive \nodoc\ _Text
  """
  A part's text, or `-` for a part that is not there.
  """
  fun apply(n: (Node | None)): String =>
    match n
    | let node: Node => node.text()
    | None => "-"
    end

  fun kind(k: (TokenKind | None)): String =>
    match k
    | let t: TokenKind => t.name()
    | None => "-"
    end

primitive \nodoc\ _TypeText
  """
  A type as one line, so that a test asserts a whole classification at
  once: `pkg.Name[args] cap ^`, `(A | B)`, `(A & B)`, `(A, B)`, `A->B`,
  `{cap name[params](args): R ?} cap ^`, `this`, a bare cap, and `-`
  for none.
  """
  fun apply(t: (TypeExpr | None)): String =>
    match t
    | let e: TypeExpr => _expr(e)
    | None => "-"
    end

  fun arg(a: (TypeArg | None)): String =>
    match a
    | let e: TypeExpr => _expr(e)
    | let v: ValueArg => "#" + v.node().text()
    | None => "-"
    end

  fun _expr(t: TypeExpr): String =>
    match \exhaustive\ t
    | let n: NominalType =>
      let out = recover iso String end
      match n.package()
      | let p: Node => out.append(p.text() + ".")
      end
      out.append(_Text(n.name()))
      if n.type_args().size() > 0 then
        out.append("[" + _args(n.type_args()) + "]")
      end
      match n.cap()
      | let c: TokenKind => out.append(" " + c.name())
      end
      match n.ephemeral()
      | let e: TokenKind => out.append(" " + e.name())
      end
      consume out
    | let u: UnionType => "(" + _each(u.members(), " | ") + ")"
    | let i: IsectType => "(" + _each(i.members(), " & ") + ")"
    | let tu: TupleType => "(" + _each(tu.members(), ", ") + ")"
    | let v: ViewpointType => apply(v.left()) + "->" + apply(v.right())
    | let l: LambdaType =>
      let out = recover iso String end
      out.append(if l.is_bare() then "@{" else "{" end)
      match l.receiver_cap()
      | let c: TokenKind => out.append(c.name() + " ")
      end
      match l.name()
      | let n: Node => out.append(n.text())
      end
      if l.type_params().size() > 0 then
        out.append("[")
        for (i, tp) in l.type_params().pairs() do
          if i > 0 then out.append(", ") end
          out.append(_Text(tp.name()))
        end
        out.append("]")
      end
      out.append("(" + _each(l.param_types(), ", ") + ")")
      match l.return_type()
      | let r: TypeExpr => out.append(": " + _expr(r))
      end
      if l.is_partial() then out.append(" ?") end
      out.append("}")
      match l.cap()
      | let c: TokenKind => out.append(" " + c.name())
      end
      match l.ephemeral()
      | let e: TokenKind => out.append(" " + e.name())
      end
      consume out
    | let _: ThisType => "this"
    | let c: CapType => c.cap().name()
    end

  fun _each(ts: Array[TypeExpr] val, sep: String): String =>
    let out = recover iso String end
    for (i, t) in ts.pairs() do
      if i > 0 then out.append(sep) end
      out.append(_expr(t))
    end
    consume out

  fun _args(ts: Array[TypeArg] val): String =>
    let out = recover iso String end
    for (i, t) in ts.pairs() do
      if i > 0 then out.append(", ") end
      out.append(arg(t))
    end
    consume out

primitive \nodoc\ _First
  """
  The first entity, field, method or FFI declaration of a source, and
  a type's classification as a field's declared type, for tests that
  look at one item.
  """
  fun entity(h: TestHelper, src: String val): EntityDecl ? =>
    let es = _ParseText(src).entities()
    h.assert_eq[USize](1, es.size(), src + ": one entity")
    es(0)?

  fun field(h: TestHelper, src: String val): FieldDecl ? =>
    match entity(h, src)?.members()(0)?
    | let f: FieldDecl => f
    else
      h.fail(src + ": the first member is not a field")
      error
    end

  fun method(h: TestHelper, src: String val): MethodDecl ? =>
    match entity(h, src)?.members()(0)?
    | let m: MethodDecl => m
    else
      h.fail(src + ": the first member is not a method")
      error
    end

  fun ffi(h: TestHelper, src: String val): FfiDecl ? =>
    let ds = _ParseText(src).ffi_decls()
    h.assert_eq[USize](1, ds.size(), src + ": one ffi declaration")
    ds(0)?

  fun field_type(h: TestHelper, type_text: String val): String ? =>
    """
    The classification of `type_text` as a field's declared type.
    """
    _TypeText(field(h, "class C\n  let x: " + type_text + "\n")?
      .declared_type())

class \nodoc\ iso _TestTreeViews is UnitTest
  fun name(): String => "parse/views: the tree's accessors"

  fun apply(h: TestHelper) =>
    """
    `docstring` is the module's leading string and nothing else;
    `use_commands` holds every use in order, an FFI declaration as an
    `FfiDecl`; `ffi_decls` is that filtered; `entities` is every entity.
    """
    let tree = _ParseText(
      "\"\"\"Doc\"\"\"\nuse \"a\"\nuse @f[U8]()\nuse b = \"c\"\n" +
      "class A\nprimitive B\n")
    h.assert_eq[String]("\"\"\"Doc\"\"\"", _Text(tree.docstring()))
    let kinds = recover iso String end
    for u in tree.use_commands().values() do
      match u
      | let p: PackageUse => kinds.append("P" + _Text(p.locator()) + " ")
      | let d: FfiDecl => kinds.append("F" + _Text(d.name()) + " ")
      end
    end
    h.assert_eq[String]("P\"a\" Ff P\"c\" ", consume kinds)
    h.assert_eq[USize](1, tree.ffi_decls().size())
    let names = recover iso String end
    for e in tree.entities().values() do
      names.append(e.keyword().name() + ":" + _Text(e.name()) + " ")
    end
    h.assert_eq[String]("TkClass:A TkPrimitive:B ", consume names)
    // No docstring: a string after an entity is that entity's, and a
    // file starting with a use has none.
    h.assert_eq[String]("-", _Text(_ParseText("use \"a\"\n").docstring()))
    h.assert_eq[String]("-",
      _Text(_ParseText("class A\n  \"\"\"D\"\"\"\n").docstring()))
    h.assert_eq[USize](0, _ParseText("").use_commands().size())
    h.assert_eq[USize](0, _ParseText("").entities().size())

class \nodoc\ iso _TestPackageUseView is UnitTest
  fun name(): String => "parse/views: PackageUse"

  fun apply(h: TestHelper) =>
    """
    Alias, locator and guard, present and absent; a bare string after
    `if` is the guard and not a second locator; the broken forms
    `use = "a"` (no alias, no locator: the specifier was reported at
    `=`), `use x "a"` (the alias, no locator: the string is the
    command's error item) and `use "a" if` (a locator, no guard).
    """
    let rows: Array[(String, String, String, String)] = [
      ("use \"a\"\n", "-", "\"a\"", "-")
      ("use x = \"a\" if linux\n", "x", "\"a\"", "linux")
      ("use \"x\" if \"y\"\n", "-", "\"x\"", "\"y\"")
      ("use \"a\" if (linux or osx)\n", "-", "\"a\"", "(linux or osx)")
      ("use = \"a\"\n", "-", "-", "-")
      ("use x \"a\"\n", "x", "-", "-")
      ("use \"a\" if\n", "-", "\"a\"", "-")
    ]
    for (src, alias, locator, guard) in rows.values() do
      let commands = _ParseText(src).use_commands()
      h.assert_eq[USize](1, commands.size(), src)
      try
        match commands(0)?
        | let u: PackageUse =>
          h.assert_eq[String](alias, _Text(u.alias()), src + " alias")
          h.assert_eq[String](locator, _Text(u.locator()), src + " locator")
          h.assert_eq[String](guard, _Text(u.guard()), src + " guard")
          h.assert_eq[USize](0, u.span().start, src + " span start")
          h.assert_true(u.node().kind() is NdUse, src + " node")
        | let _: FfiDecl => h.fail(src + ": an FfiDecl")
        end
      end
    end

class \nodoc\ iso _TestFfiDeclView is UnitTest
  fun name(): String => "parse/views: FfiDecl"

  fun apply(h: TestHelper) =>
    """
    Every accessor over `use @f[U8](a: U8, ...)?`, each from its stated
    node; a string name decoded; an annotated return type and an
    annotated parameter; the alias and the guard from the `NdUse`; and
    four of the declarations of ponyc's `ffi-struct-by-value` test.
    """
    try
      let d = _First.ffi(h, "use @f[U8](a: U8, ...)?\n")?
      h.assert_true(d.node().kind() is NdUse)
      h.assert_eq[String]("f", _Text(d.name()))
      h.assert_eq[String]("f", try d.symbol() as String else "-" end)
      h.assert_eq[USize](1, d.return_type_args().size())
      h.assert_eq[String]("U8", _TypeText.arg(d.return_type_args()(0)?
        .type_arg()))
      h.assert_eq[String]("-", _Text(d.return_type_args()(0)?.annotations()))
      h.assert_eq[USize](1, d.params().size())
      h.assert_eq[String]("a", _Text(d.params()(0)?.name()))
      h.assert_eq[String]("U8", _TypeText(d.params()(0)?.declared_type()))
      h.assert_true(d.has_ellipsis())
      h.assert_true(d.is_partial())
      h.assert_eq[String]("-", _Text(d.alias()))
      h.assert_eq[String]("-", _Text(d.guard()))
      h.assert_eq[USize](0, d.span().start)
      h.assert_eq[USize]("use @f[U8](a: U8, ...)?".size(), d.span().length)
    else
      h.fail("accessor")
    end
    try
      let d = _First.ffi(h, "use g = @\"f x\"[U8]() if linux\n")?
      h.assert_eq[String]("\"f x\"", _Text(d.name()))
      h.assert_eq[String]("f x", try d.symbol() as String else "-" end)
      h.assert_eq[String]("g", _Text(d.alias()))
      h.assert_eq[String]("linux", _Text(d.guard()))
      h.assert_false(d.has_ellipsis())
      h.assert_false(d.is_partial())
      h.assert_eq[USize](0, d.params().size())
    else
      h.fail("string name")
    end
    try
      let d = _First.ffi(h,
        "use @f[Point \\by_value\\](p: Point \\by_value\\ = q, n: U8)\n")?
      let r = d.return_type_args()(0)?
      h.assert_eq[String]("Point", _TypeText.arg(r.type_arg()))
      h.assert_eq[String]("\\by_value\\", _Text(r.annotations()))
      h.assert_eq[USize]("Point \\by_value\\".size(), r.span().length)
      h.assert_eq[USize](2, d.params().size())
      let p = d.params()(0)?
      h.assert_eq[String]("\\by_value\\", _Text(p.annotations()))
      h.assert_eq[String]("= q", _Text(p.default_value()))
      h.assert_eq[String]("-", _Text(d.params()(1)?.annotations()))
    else
      h.fail("annotated")
    end
    // Two return type arguments, the annotation pairing with its own.
    try
      let d = _First.ffi(h, "use @f[U8 \\a\\, U16]()\n")?
      h.assert_eq[USize](2, d.return_type_args().size())
      h.assert_eq[String]("\\a\\",
        _Text(d.return_type_args()(0)?.annotations()))
      let second = d.return_type_args()(1)?
      h.assert_eq[String]("U16", _TypeText.arg(second.type_arg()))
      h.assert_eq[String]("-", _Text(second.annotations()))
      h.assert_eq[USize](3, second.span().length)
      let e = _First.ffi(h, "use @f[U8, U16 \\b\\]()\n")?
      h.assert_eq[String]("-", _Text(e.return_type_args()(0)?.annotations()))
      h.assert_eq[String]("\\b\\",
        _Text(e.return_type_args()(1)?.annotations()))
      h.assert_eq[USize]("U16 \\b\\".size(),
        e.return_type_args()(1)?.span().length)
    else
      h.fail("two return type arguments")
    end
    // The broken forms: no name, no return type, no `(`.
    try
      let d = _First.ffi(h, "use @[U8]()\n")?
      h.assert_eq[String]("-", _Text(d.name()))
      h.assert_true(d.symbol() is None)
    else
      h.fail("no name")
    end
    try
      let d = _First.ffi(h, "use @f()\n")?
      h.assert_eq[USize](0, d.return_type_args().size())
      h.assert_eq[String]("f", _Text(d.name()))
    else
      h.fail("no return type")
    end
    try
      let d = _First.ffi(h, "use @f[U8]\n")?
      h.assert_eq[USize](0, d.params().size())
      h.assert_false(d.has_ellipsis())
    else
      h.fail("no parameters")
    end
    let example: String val =
      "use @point_sum[F64](p: Point \\by_value\\)\n" +
      "use @point_make[Point \\by_value\\](x: F64, y: F64)\n" +
      "use @rect_move[Rect \\by_value\\](r: Rect \\by_value\\, dx: I32, " +
      "dy: I32)\n" +
      "use @pony_exitcode[None](code: I32)\n"
    let got = recover iso String end
    for d in _ParseText(example).ffi_decls().values() do
      got.append(_Text(d.name()) + "[")
      for r in d.return_type_args().values() do
        got.append(_TypeText.arg(r.type_arg()))
        match r.annotations()
        | let a: Node => got.append(" " + a.text())
        end
      end
      got.append("](")
      for (i, p) in d.params().pairs() do
        if i > 0 then got.append(", ") end
        got.append(_Text(p.name()) + ": " + _TypeText(p.declared_type()))
        match p.annotations()
        | let a: Node => got.append(" " + a.text())
        end
      end
      got.append(")\n")
    end
    h.assert_eq[String](
      "point_sum[F64](p: Point \\by_value\\)\n" +
      "point_make[Point \\by_value\\](x: F64, y: F64)\n" +
      "rect_move[Rect \\by_value\\](r: Rect \\by_value\\, dx: I32, " +
      "dy: I32)\n" +
      "pony_exitcode[None](code: I32)\n", consume got)

class \nodoc\ iso _TestEntityView is UnitTest
  fun name(): String => "parse/views: EntityDecl"

  fun apply(h: TestHelper) =>
    """
    Every part present, then absent, then broken: `class` alone (no
    name), `class C[` (a type parameter with no name), `class C is`
    (no provides type), `class \\a C` (an unterminated annotation
    group, still the annotations).
    """
    try
      let e = _First.entity(h,
        "class \\a, b\\ @ iso C[A: B = D, E] is (F | G)\n" +
        "  \"\"\"Doc\"\"\"\n  let x: U8\n  fun f() => 1\n")?
      h.assert_true(e.keyword() is TkClass)
      h.assert_eq[String]("\\a, b\\", _Text(e.annotations()))
      h.assert_true(e.is_c_api())
      h.assert_eq[String]("TkIso", _Text.kind(e.cap()))
      h.assert_eq[String]("C", _Text(e.name()))
      h.assert_eq[USize](2, e.type_params().size())
      let a = e.type_params()(0)?
      h.assert_eq[String]("A", _Text(a.name()))
      h.assert_eq[String]("B", _TypeText(a.constraint()))
      h.assert_eq[String]("D", _TypeText.arg(a.default()))
      h.assert_eq[String]("E", _Text(e.type_params()(1)?.name()))
      h.assert_eq[String]("(F | G)", _TypeText(e.provides()))
      h.assert_eq[String]("\"\"\"Doc\"\"\"", _Text(e.docstring()))
      h.assert_eq[USize](2, e.members().size())
      match e.members()(0)?
      | let f: FieldDecl => h.assert_eq[String]("x", _Text(f.name()))
      else
        h.fail("first member")
      end
      match e.members()(1)?
      | let m: MethodDecl => h.assert_eq[String]("f", _Text(m.name()))
      else
        h.fail("second member")
      end
    else
      h.fail("present")
    end
    try
      let e = _First.entity(h, "primitive P\n")?
      h.assert_true(e.keyword() is TkPrimitive)
      h.assert_eq[String]("-", _Text(e.annotations()))
      h.assert_false(e.is_c_api())
      h.assert_eq[String]("-", _Text.kind(e.cap()))
      h.assert_eq[USize](0, e.type_params().size())
      h.assert_eq[String]("-", _TypeText(e.provides()))
      h.assert_eq[String]("-", _Text(e.docstring()))
      h.assert_eq[USize](0, e.members().size())
    else
      h.fail("absent")
    end
    try
      h.assert_eq[String]("-", _Text(_First.entity(h, "class\n")?.name()))
      let broken = _First.entity(h, "class C[\n")?
      h.assert_eq[USize](1, broken.type_params().size())
      h.assert_eq[String]("-", _Text(broken.type_params()(0)?.name()))
      h.assert_eq[String]("-",
        _TypeText(_First.entity(h, "class C is\n")?.provides()))
      h.assert_eq[String]("\\a",
        _Text(_First.entity(h, "class \\a C\n")?.annotations()))
    else
      h.fail("broken")
    end

class \nodoc\ iso _TestFieldView is UnitTest
  fun name(): String => "parse/views: FieldDecl"

  fun apply(h: TestHelper) =>
    """
    The docstring rule: after `=`, the second part when it is a
    string, so a string value alone is the initialiser and not the
    docstring; without `=`, the string child. The broken forms: no
    name, no colon (the type is read but is not "after `TkColon`").
    """
    let rows: Array[(String, String, String, String, String)] = [
      ("var x: U8", "TkVar", "x", "U8", "-")
      ("let x: String = \"s\"", "TkLet", "x", "String", "-")
      ("let x: String = \"s\" \"\"\"d\"\"\"", "TkLet", "x", "String",
        "\"\"\"d\"\"\"")
      ("embed x: U8 = 1 + 2 \"d\"", "TkEmbed", "x", "U8", "\"d\"")
      ("let x: U8 \"d\"", "TkLet", "x", "U8", "\"d\"")
      ("let : U8", "TkLet", "-", "U8", "-")
      ("let x U8", "TkLet", "x", "-", "-")
    ]
    for (text, keyword, name', type', doc) in rows.values() do
      try
        let f = _First.field(h, "class C\n  " + text + "\n")?
        h.assert_eq[String](keyword, f.keyword().name(), text + " keyword")
        h.assert_eq[String](name', _Text(f.name()), text + " name")
        h.assert_eq[String](type', _TypeText(f.declared_type()),
          text + " type")
        h.assert_eq[String](doc, _Text(f.docstring()), text + " docstring")
      else
        h.fail(text)
      end
    end
    try
      let f = _First.field(h, "class C\n  let x: String = \"s\"\n")?
      h.assert_eq[String]("\"s\"", _Text(f.initialiser()))
      let g = _First.field(h, "class C\n  let x: U8 = 1 + 2 \"d\"\n")?
      h.assert_eq[String]("1 + 2", _Text(g.initialiser()))
      h.assert_eq[String]("-",
        _Text(_First.field(h, "class C\n  let x: U8\n")?.initialiser()))
    else
      h.fail("initialiser")
    end

class \nodoc\ iso _TestMethodView is UnitTest
  fun name(): String => "parse/views: MethodDecl"

  fun apply(h: TestHelper) =>
    """
    Every part over `fun \\a\\ iso f[A](x: U8, ...): B ? "d" => 1`;
    the capability before the colon and a bare-capability return type
    after it: `fun iso f(): val` and `fun f(): iso`; a missing name,
    `fun iso (): val`; a bare method's `@`; a behaviour and a
    constructor; and a bodiless method.
    """
    try
      let m = _First.method(h,
        "class C\n  fun \\a\\ iso f[A](x: U8, ...): B ? \"d\" => 1\n")?
      h.assert_true(m.keyword() is TkFun)
      h.assert_eq[String]("\\a\\", _Text(m.annotations()))
      h.assert_eq[String]("TkIso", _Text.kind(m.cap()))
      h.assert_eq[String]("f", _Text(m.name()))
      h.assert_eq[USize](1, m.type_params().size())
      h.assert_eq[String]("A", _Text(m.type_params()(0)?.name()))
      h.assert_eq[USize](1, m.params().size())
      h.assert_eq[String]("x", _Text(m.params()(0)?.name()))
      h.assert_true(m.has_ellipsis())
      h.assert_eq[String]("B", _TypeText(m.return_type()))
      h.assert_true(m.is_partial())
      h.assert_eq[String]("\"d\"", _Text(m.docstring()))
      h.assert_eq[String]("1", _Text(m.body()))
    else
      h.fail("present")
    end
    let rows: Array[(String, String, String, String)] = [
      ("fun iso f(): val", "TkIso", "f", "TkVal")
      ("fun f(): iso", "-", "f", "TkIso")
      ("fun iso (): val", "TkIso", "-", "TkVal")
      ("fun @f(): U8", "TkAt", "f", "U8")
      ("be f()", "-", "f", "-")
      ("new iso create()", "TkIso", "create", "-")
      ("fun f", "-", "f", "-")
    ]
    for (text, cap, name', ret) in rows.values() do
      try
        let m = _First.method(h, "class C\n  " + text + "\n")?
        h.assert_eq[String](cap, _Text.kind(m.cap()), text + " cap")
        h.assert_eq[String](name', _Text(m.name()), text + " name")
        h.assert_eq[String](ret, _TypeText(m.return_type()), text + " return")
        h.assert_eq[USize](0, m.params().size(), text + " params")
        h.assert_false(m.has_ellipsis(), text + " ellipsis")
        h.assert_false(m.is_partial(), text + " partial")
        h.assert_eq[String]("-", _Text(m.body()), text + " body")
      else
        h.fail(text)
      end
    end

class \nodoc\ iso _TestMethodDocstringRule is UnitTest
  fun name(): String => "parse/views: MethodDecl.docstring is ponyc's rule"

  fun apply(h: TestHelper) =>
    """
    A `fun` whose return type is absent or a nominal named `None`, in
    any package, with any capability, grouped or not, has ponyc's
    `None` appended to its body before `sugar_docstring` runs, so a
    body that is only a string is its docstring; for any other method
    a body
    that is only a string has none, and one that starts with a string
    and continues has it, whether the continuation is on a new line or
    after `;`; a string then `;` and nothing more has none; a bodiless
    method with a string has it; and the string before `=>` wins over
    the body's. Probed on ponyc with `--pass=sugar --astpackage`.
    """
    let rows: Array[(String, String, String)] = [
      ("fun f() => \"s\"", "\"s\"", "\"s\"")
      ("fun f(): None => \"s\"", "\"s\"", "\"s\"")
      ("fun f(): (None) => \"s\"", "\"s\"", "\"s\"")
      ("fun f(): builtin.None => \"s\"", "\"s\"", "\"s\"")
      ("fun f(): None val => \"s\"", "\"s\"", "\"s\"")
      ("fun f(): (None | U8) => \"s\"", "-", "\"s\"")
      ("fun f(): U8 => \"s\"", "-", "\"s\"")
      ("be f() => \"s\"", "-", "\"s\"")
      ("new create() => \"s\"", "-", "\"s\"")
      ("fun f(): U8 =>\n    \"s\"\n    2", "\"s\"", "\"s\"\n    2")
      ("fun f(): U8 => \"s\"; 2", "\"s\"", "\"s\"; 2")
      ("fun f(): U8 => \"s\";", "-", "\"s\";")
      ("fun f() => \"s\";", "\"s\"", "\"s\";")
      ("fun f() \"d\"", "\"d\"", "-")
      ("fun f() \"d\" => \"s\"; 2", "\"d\"", "\"s\"; 2")
      ("fun f(): U8 => 1; \"s\"", "-", "1; \"s\"")
      ("fun f() => 1; \"s\"", "-", "1; \"s\"")
    ]
    for (text, doc, body) in rows.values() do
      try
        let m = _First.method(h, "class C\n  " + text + "\n")?
        h.assert_eq[String](doc, _Text(m.docstring()), text + " docstring")
        h.assert_eq[String](body, _Text(m.body()), text + " body")
      else
        h.fail(text)
      end
    end
    // The `;` with nothing after it is reported, as ponyc reports it.
    _Exactly(h, "class C\n  fun f() => \"s\";\n", [
      ("parse/expected", 24, "syntax error: expected value, found the end " +
        "of the file")
    ], "a lone semicolon")

class \nodoc\ iso _TestParamViews is UnitTest
  fun name(): String => "parse/views: ParamDecl and TypeParamDecl"

  fun apply(h: TestHelper) =>
    """
    A parameter's name, type and default; a type parameter's name,
    constraint and default, including `[A = Bar]` with no constraint;
    the broken forms `(x U8)`, `[: B]`, `[A:]`, `[A =]`; `(: U8)` has
    no parameter at all, since the list is entered only at a name or
    an ellipsis.
    """
    let params: Array[(String, String, String, String)] = [
      ("x: U8", "x", "U8", "-")
      ("x: U8 = 1", "x", "U8", "= 1")
      ("x U8", "x", "-", "-")
    ]
    for (text, name', type', default') in params.values() do
      try
        let m = _First.method(h, "class C\n  fun f(" + text + ")\n")?
        h.assert_eq[USize](1, m.params().size(), text + " count")
        let p = m.params()(0)?
        h.assert_eq[String](name', _Text(p.name()), text + " name")
        h.assert_eq[String](type', _TypeText(p.declared_type()),
          text + " type")
        h.assert_eq[String](default', _Text(p.default_value()),
          text + " default")
        h.assert_eq[String]("-", _Text(p.annotations()), text + " annotations")
      else
        h.fail(text)
      end
    end
    try
      h.assert_eq[USize](0,
        _First.method(h, "class C\n  fun f(: U8)\n")?.params().size())
    else
      h.fail("(: U8)")
    end
    let type_params: Array[(String, String, String, String)] = [
      ("A", "A", "-", "-")
      ("A: B", "A", "B", "-")
      ("A = Bar", "A", "-", "Bar")
      ("A: B = 3", "A", "B", "#3")
      (": B", "-", "B", "-")
      ("A:", "A", "-", "-")
      ("A =", "A", "-", "-")
    ]
    for (text, name', constraint, default') in type_params.values() do
      try
        let e = _First.entity(h, "class C[" + text + "]\n")?
        h.assert_eq[USize](1, e.type_params().size(), text + " count")
        let tp = e.type_params()(0)?
        h.assert_eq[String](name', _Text(tp.name()), text + " name")
        h.assert_eq[String](constraint, _TypeText(tp.constraint()),
          text + " constraint")
        h.assert_eq[String](default', _TypeText.arg(tp.default()),
          text + " default")
      else
        h.fail(text)
      end
    end

class \nodoc\ iso _TestTypeOfForms is UnitTest
  fun name(): String => "parse/views: TypeOf classifies every form"

  fun apply(h: TestHelper) =>
    """
    Each type form as a field's declared type, and the asymmetric
    cases: `pkg.` (a package, no name), `A->` (no right side), `()`
    (nothing), `((A))` (grouping is transparent), a bare capability, a
    generic capability, and a value type argument.
    """
    let rows: Array[(String, String)] = [
      ("A", "A")
      ("pkg.A", "pkg.A")
      ("pkg.", "pkg.-")
      ("A[B, C val]", "A[B, C TkVal]")
      ("A iso^", "A TkIso TkEphemeral")
      ("A[3]", "A[#3]")
      ("A[#(1 + 2)]", "A[##(1 + 2)]")
      ("A[]", "A")
      ("this", "this")
      ("iso", "TkIso")
      ("#read", "TkCapRead")
      ("(A)", "A")
      ("((A))", "A")
      ("()", "-")
      ("(A, B)", "(A, B)")
      ("(A, (B, C))", "(A, (B, C))")
      ("A->B", "A->B")
      ("A->B->C", "A->B->C")
      ("A->", "A->-")
      ("{(A, B): C} val", "{(A, B): C} TkVal")
      ("{iso f[T](A): B ?} ref^", "{TkIso f[T](A): B ?} TkRef TkEphemeral")
      ("@{(A)}", "@{(A)}")
      ("{()}", "{()}")
      ("{f} val", "{f()} TkVal")
      ("{): val}", "{(): TkVal}")
      ("{iso}", "{TkIso ()}")
      ("{(A) iso", "{(A)}")
      ("(|)", "()")
      ("A iso!", "A TkIso TkAliased")
      ("->B", "-->B")
      ("(A, )", "(A)")
      ("(A | B)", "(A | B)")
      ("(A & B)", "(A & B)")
      ("(A |)", "(A)")
      ("(A | B, C)", "((A | B), C)")
    ]
    for (text, expected) in rows.values() do
      try
        h.assert_eq[String](expected, _First.field_type(h, text)?, text)
      else
        h.fail(text)
      end
    end
    // A field with no type at all takes `TypeOf`'s last arm.
    try
      h.assert_eq[String]("-",
        _TypeText(_First.field(h, "class C\n  let x: = 1\n")?
          .declared_type()))
    else
      h.fail("no type")
    end
    // One member is still a union, and an empty run is one with no
    // members and the node's span.
    try
      match _First.field(h, "class C\n  let x: (A |)\n")?.declared_type()
      | let u: UnionType => h.assert_eq[USize](1, u.members().size())
      else
        h.fail("(A |) is not a union")
      end
      match _First.field(h, "class C\n  let x: (|)\n")?.declared_type()
      | let u: UnionType =>
        h.assert_eq[USize](0, u.members().size())
        h.assert_eq[USize](u.node().span().start, u.span().start)
        h.assert_eq[USize](u.node().span().length, u.span().length)
      else
        h.fail("(|) is not a union")
      end
    else
      h.fail("one member")
    end
    // A viewpoint nests right, so `A->B->C` is `A->(B->C)`.
    try
      let f = _First.field(h, "class C\n  let x: A->B->C\n")?
      match f.declared_type()
      | let v: ViewpointType =>
        h.assert_true(
          match v.right() | let _: ViewpointType => true else false end,
          "right is a viewpoint")
        h.assert_true(
          match v.left() | let _: NominalType => true else false end,
          "left is nominal")
      else
        h.fail("not a viewpoint")
      end
    end

class \nodoc\ iso _TestTypeOfFolds is UnitTest
  fun name(): String => "parse/views: unions and intersections fold as runs"

  fun apply(h: TestHelper) =>
    """
    Inside the parentheses an infix type needs: `A | B | C` is one
    union of three; `A | B & C | D` is a union of `[A | B] & C` and
    `D`; `A & B | C` is a union of `A & B` and `C`; `A | (B | C)` is a
    union of two whose second member is a union; a run that closes
    with no member is dropped rather than carried into the next run,
    where its span, the node's, would reach past the next run's; a
    run's span covers its members.
    """
    let rows: Array[(String, String)] = [
      ("(A | B | C)", "(A | B | C)")
      ("(A | B & C | D)", "(((A | B) & C) | D)")
      ("(A & B | C)", "((A & B) | C)")
      ("(A | (B | C))", "(A | (B | C))")
      ("(A & B & C | D & E)", "(((A & B & C) | D) & E)")
      ("(| & A |)", "((A))")
      ("(| & A &)", "(A)")
    ]
    for (text, expected) in rows.values() do
      try
        h.assert_eq[String](expected, _First.field_type(h, text)?, text)
      else
        h.fail(text)
      end
    end
    try
      let f = _First.field(h, "class C\n  let x: (A | B & C | D)\n")?
      match f.declared_type()
      | let outer: UnionType =>
        h.assert_eq[USize](2, outer.members().size())
        h.assert_eq[USize]("A | B & C | D".size(), outer.span().length)
        h.assert_true(outer.node().kind() is NdInfixType)
        match outer.members()(0)?
        | let inner: IsectType =>
          h.assert_eq[USize]("A | B & C".size(), inner.span().length)
          h.assert_true(inner.node() == outer.node(), "one node")
          match inner.members()(0)?
          | let innermost: UnionType =>
            h.assert_eq[USize]("A | B".size(), innermost.span().length)
          else
            h.fail("innermost")
          end
        else
          h.fail("inner")
        end
      else
        h.fail("outer")
      end
    end

class \nodoc\ iso _TestMembersHoldingAnError is UnitTest
  fun name(): String => "parse/views: a member list holding an error item"

  fun apply(h: TestHelper) =>
    """
    An error item between two members is skipped, and the members
    around it keep their order.
    """
    let src = "class C\n  let x: U8\n  junk\n  fun f() => 1\n"
    try
      let e = _First.entity(h, src)?
      h.assert_eq[USize](2, e.members().size())
      match e.members()(0)?
      | let f: FieldDecl => h.assert_eq[String]("x", _Text(f.name()))
      else
        h.fail("field")
      end
      match e.members()(1)?
      | let m: MethodDecl => h.assert_eq[String]("f", _Text(m.name()))
      else
        h.fail("method")
      end
    else
      h.fail("entity")
    end
    for v in _Check(src).values() do h.fail(v.string()) end

class \nodoc\ iso _TestViewRows is UnitTest
  fun name(): String => "parse/views: PartsUnique fires and ViewsNest holds"

  fun apply(h: TestHelper) =>
    """
    `PartsUnique` on hand-built fields the grammar never builds: two
    name tokens; two strings without `=`, where the docstring is the
    `TkString` child; and two strings after `=`, where the first is
    the value and the rule is positional, so nothing fires. `ViewsNest`
    cannot be reached through a tree whose structural rows hold, since
    a child's span lies inside its parent's by construction and the
    fold drops a run with no member; the rows report nothing over the
    seeds, which hold every type form.
    """
    // NdModule[NdClassDef[TkClass TkId NdMembers[NdField[...]]] TkEof]
    // over one byte per token.
    let two_names: Array[SyntaxElement] val = [
      (NdModule, 0, 10); (NdClassDef, 0, 8); (TkClass, 0, 1); (TkId, 1, 1)
      (NdMembers, 2, 5); (NdField, 2, 4); (TkLet, 2, 1); (TkId, 3, 1)
      (TkId, 4, 1); (TkEof, 5, 1)
    ]
    _rows(h, "cCLxy", two_names, "PartsUnique at element 5", "two names")
    let two_strings: Array[SyntaxElement] val = [
      (NdModule, 0, 14); (NdClassDef, 0, 12); (TkClass, 0, 1); (TkId, 1, 1)
      (NdMembers, 2, 9); (NdField, 2, 8); (TkLet, 2, 1); (TkId, 3, 1)
      (TkColon, 4, 1); (NdNominal, 5, 2); (TkId, 5, 1); (TkString, 6, 1)
      (TkString, 7, 1); (TkEof, 8, 1)
    ]
    _rows(h, "cCLx:Uss", two_strings, "PartsUnique at element 5",
      "two strings without a value")
    let value_then_string: Array[SyntaxElement] val = [
      (NdModule, 0, 15); (NdClassDef, 0, 13); (TkClass, 0, 1); (TkId, 1, 1)
      (NdMembers, 2, 10); (NdField, 2, 9); (TkLet, 2, 1); (TkId, 3, 1)
      (TkColon, 4, 1); (NdNominal, 5, 2); (TkId, 5, 1); (TkAssign, 6, 1)
      (TkString, 7, 1); (TkString, 8, 1); (TkEof, 9, 1)
    ]
    _rows(h, "cCLx:U=ss", value_then_string, "",
      "a string value then a docstring")
    for src in _Seeds().values() do
      for v in _Check(src).values() do
        h.fail(v.string() + " for a seed")
      end
    end

  fun _rows(h: TestHelper, src: String val, elems: Array[SyntaxElement] val,
    expected: String, label: String)
  =>
    let tree = SyntaxTree._create(source.SourceFile("/t", "t.pony", src),
      elems)
    let got: String val = ", ".join(
      Iter[TreeViolation](
        TreeCheck(tree, recover val Array[diag.Diagnostic] end).values())
        .map[String]({(v) => v.string() }))
    h.assert_eq[String](expected, got, label)
